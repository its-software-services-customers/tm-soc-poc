#!/usr/bin/perl

use strict;
use warnings;
use JSON qw( decode_json );

my $HOSPCODE = $ENV{'HOSPCODE'};
my $KAFKA_BOOTSTRAP_SERVERS = $ENV{'KAFKA_BOOTSTRAP_SERVERS'};

my $NIFI_VERSION = $ENV{NIFI_VERSION};
my $FLOW_FILE = "02-nifi-pg/his-gw-moph.json";
my $PROGRAM_BIN = "$ENV{HOME}/nifi-toolkit-$NIFI_VERSION/bin/cli.sh";
my $NIFI_URL = 'http://localhost:8080';
my $NIFI_URL_INT = 'http://nifi-registry:18080';
my $REGISTRY_URL = 'http://localhost:18080';
my $FLOW_NAME = 'his-gw';
my $BUCKET = 'local';
my $REGISTRY_CLIENT = 'local';
my $PG_NAME = 'Gateway2Moph';
my $CONTEXT_NAME = 'context';
my $PG_SIGNATURE_FILE = "$ENV{HOME}/data/pg-signature.txt";

my $PASSWORD_FILE = "$ENV{HOME}/certs/hospcode-${HOSPCODE}.user.pasword";
my $KEYSTORE_FILE = "/kafka/certs/hospcode-${HOSPCODE}.user.keystore.jks";
my $TRUSTSTORE_FILE = "/kafka/certs/hospcode-${HOSPCODE}.cluster-ca.truststore.jks";

# It is good idea to setup NIFI toolkit here because NIFI version could be changed based on what we set in docker-compose.yaml
setup_nifi_toolkit();

wait_server_start();

$ENV{'JAVA_HOME'} = '/usr'; # To suppress warning from cli.sh

my $bucketId = get_bucket_id($BUCKET);
if ($bucketId eq '')
{
    # Create new bucket if not exist
    print("### Bucket [$BUCKET] not foud so create the new one...\n");

    create_bucket($BUCKET);
    $bucketId = get_bucket_id($BUCKET);
}

my $flowId = get_flow_id($bucketId, $FLOW_NAME);
if ($flowId eq '')
{
    # Create new flow if not exist
    print("### Flow [$FLOW_NAME] not foud in bucket [$BUCKET], so create the new one...\n");

    create_flow($bucketId, $FLOW_NAME);
    $flowId = get_flow_id($bucketId, $FLOW_NAME);
}

my ($isFileChanged, $signature) = is_signature_changed($PG_SIGNATURE_FILE, $FLOW_FILE);
if ($isFileChanged == 1)
{
    import_flow_version($flowId, $FLOW_FILE);
    execute_cmd("echo '$signature' > $PG_SIGNATURE_FILE");
}

my $regClientId = get_registry_client_id($REGISTRY_CLIENT);
if ($regClientId eq '')
{
    # Create new client registry if not exist
    print("### Registry client [$REGISTRY_CLIENT] not foud, so create the new one...\n");

    create_registry_client($REGISTRY_CLIENT);
    $regClientId = get_registry_client_id($REGISTRY_CLIENT);
}

my $pgId = get_pg_deployed($PG_NAME);
my $latestVersion = get_latest_flow_version($flowId);
if ($pgId eq '')
{
    # No process group has been deploy    
    pg_import($bucketId, $flowId, $latestVersion);
    # Get imported process group id
    $pgId = get_pg_deployed($PG_NAME);
}
else
{
    # Update existing flow
    pg_change_version($pgId, $latestVersion);
}

print("### Current process group ID is [$pgId]\n");

my $paramContextId = get_param_context($CONTEXT_NAME);

disable_svc_and_stop($pgId);
setup_param_values($paramContextId);
enable_svc_and_start($pgId);

exit(0);
# =====

sub wait_server_start
{
    my @services = ("$REGISTRY_URL", "$NIFI_URL");

    my $sec = 5;
    my $quota = 24;
    my $success = 0;

    foreach my $url ( @services )
    {
        my $cmd = "curl -s $url";

        # Error
        for (my $i = 1; $i <= $quota; $i++)
        {
            my $output = `$cmd`;
            if ($?)
            {
                print("@@@ [$i / $quota] Server [$url] is not available, will try in the next $sec seconds!!!\n");
                #print("@@@ [$output]!!!\n");

                sleep($sec);
            }
            else
            {
                print("@@@ [$i / $quota] Success to connect [$url]\n");
                $success++;
                last;
            }
        }
    }

    if ($success != 2)
    {
        print("@@@ Error service(s) not available!!!\n");
        exit(1);
    }
}

sub setup_nifi_toolkit
{
    if (-e $PROGRAM_BIN)
    {
        print("@@@ No need to download NIFI toolkit version [$NIFI_VERSION], it is already installed\n");
        return;
    }

    my $url = "https://archive.apache.org/dist/nifi/$NIFI_VERSION/nifi-toolkit-$NIFI_VERSION-bin.tar.gz";
    my $cmd = '';
    my $out = '';

    $cmd = "curl -LO $url; tar -xvf nifi-toolkit-$NIFI_VERSION-bin.tar.gz";
    $out = execute_cmd($cmd);

    $cmd = "mv nifi-toolkit-$NIFI_VERSION $ENV{HOME}; rm nifi-toolkit-$NIFI_VERSION-bin.tar.gz";    
    $out = execute_cmd($cmd);

    print("@@@ Done - Installed NIFI version [$NIFI_VERSION]\n");
}

sub is_signature_changed
{
    my ($signatureFile, $pgFile) = @_;

    my $previousSig = `cat $signatureFile`;
    chomp($previousSig);

    my $currentSig = `sha1sum $pgFile`;
    chomp($currentSig);

    print("### Existing SHA [$previousSig]\n");
    print("### New SHA [$currentSig]\n");

    if ($previousSig ne $currentSig)
    {
        print("### File [$pgFile] has been changed\n");
        return (1, $currentSig);
    }

    print("### File [$pgFile] has NOT been changed\n");

    return (0, $previousSig);
}

sub disable_svc_and_stop
{
    my ($pgId) = @_;

    print("### Disable services & stop process group [$pgId]...\n");
    
    my $cmd2 = "$PROGRAM_BIN nifi pg-stop -u $NIFI_URL --processGroupId $pgId";
    my $out2 = execute_cmd($cmd2);  

    my $cmd1 = "$PROGRAM_BIN nifi pg-disable-services -u $NIFI_URL --processGroupId $pgId";
    my $out1 = execute_cmd($cmd1); 
}

sub enable_svc_and_start
{
    my ($pgId) = @_;

    print("### Enable services & start process group [$pgId]...\n");

    my $cmd1 = "$PROGRAM_BIN nifi pg-enable-services -u $NIFI_URL --processGroupId $pgId";
    my $out1 = execute_cmd($cmd1);

    my $cmd2 = "$PROGRAM_BIN nifi pg-start -u $NIFI_URL --processGroupId $pgId";
    my $out2 = execute_cmd($cmd2);   
}

sub setup_param_values
{
    my ($paramContextId) = @_;

    print("### Setting param values for [$paramContextId]...\n");
    my $commonPart = "$PROGRAM_BIN nifi set-param -u $NIFI_URL --paramContextId $paramContextId --paramName";

    my $cmd1 = "$commonPart VAR_KAFKA_PASSWORD --paramValue notused";
    my $out1 = execute_cmd($cmd1);

    my $password = execute_cmd("cat $PASSWORD_FILE");

    my $cmd2 = "$commonPart VAR_KEYSTORE_PASSWORD --paramValue $password";
    my $out2 = execute_cmd($cmd2);

    my $cmd3 = "$commonPart VAR_KAFKA_BOOTSTRAP --paramValue ${KAFKA_BOOTSTRAP_SERVERS}";
    my $out3 = execute_cmd($cmd3);

    my $cmd4 = "$commonPart VAR_KAFKA_KEYSTORE_FILE --paramValue ${KEYSTORE_FILE}";
    my $out4 = execute_cmd($cmd4);

    my $cmd5 = "$commonPart VAR_KAFKA_TRUSTSTORE_FILE --paramValue ${TRUSTSTORE_FILE}";
    my $out5 = execute_cmd($cmd5);

    my $cmd6 = "$commonPart VAR_KAFKA_TOPIC --paramValue hosp-$ENV{ZONE}-$ENV{PROVINCE}-$HOSPCODE";
    my $out6 = execute_cmd($cmd6);
}

sub get_param_context
{
    my ($contextName) = @_;

    print("### Getting param context [$contextName]...\n");

    my $cmd = "$PROGRAM_BIN nifi list-param-contexts -u $NIFI_URL | grep $contextName";
    my $line = execute_cmd($cmd, 1);

    if ($line eq '')
    {
        return '';
    }

    # Suppose to get only 1 line here
    my ($no, $id, $name, $whatever) = ($line =~ m/^(.+?)\s+(.+?)\s+(.+?)\s+(.+)$/);

    return $id;
}

sub get_pg_deployed
{
    my ($pgName) = @_;

    print("### Getting process group [$pgName]...\n");

    my $cmd = "$PROGRAM_BIN nifi pg-list -u $NIFI_URL | grep $pgName";
    my $line = execute_cmd($cmd, 1);

    if ($line eq '')
    {
        return '';
    }

    # Suppose to get only 1 line here
    my ($no, $name, $id, $whatever) = ($line =~ m/^(.+?)\s+(.+?)\s+(.+?)\s+(.+)$/);

    return $id;
}

sub pg_import
{
    my ($buketId, $flowId, $version) = @_;

    print("### Importing process group...\n");
    print("### For Bucket=[$buketId] Flow=[$flowId] Version=[$version]...\n");

    my $cmd = "$PROGRAM_BIN nifi pg-import -u $NIFI_URL --bucketIdentifier $buketId --flowIdentifier $flowId --flowVersion $version";
    my $output = execute_cmd($cmd);  
}

sub pg_change_version
{
    my ($groupId, $version) = @_;

    print("### Updating process group version [$groupId] to version [$version]...\n");

    my $cmd = "$PROGRAM_BIN nifi pg-change-version -u $NIFI_URL --processGroupId $groupId --flowVersion $version";
    my $output = execute_cmd($cmd);  
}

sub get_latest_flow_version
{
    my ($flowId) = @_;

    print("### Getting flow latest version for flow [$flowId]...\n");

    my $cmd = "$PROGRAM_BIN registry list-flow-versions -u $REGISTRY_URL --flowIdentifier $flowId -ot json";
    my $json = execute_cmd($cmd);

    my $arrPtr = decode_json($json);
    my @arr = @$arrPtr;
    my $max = -1;

    foreach my $item ( @arr )
    {
        my $value = $item->{'version'};
        $value = $value + 0; # Convert to int

        if ($value > $max)
        {
            $max = $value;
        }
    }

    print("### Flow latest version is [$max]\n");
    return $max;
}

sub create_registry_client
{
    my ($name) = @_;

    print("### Creating registry client [$name]...\n");

    my $cmd = "$PROGRAM_BIN nifi create-reg-client -u $NIFI_URL --registryClientName $name --registryClientUrl ${NIFI_URL_INT}";
    my $line = execute_cmd($cmd);
}

sub get_registry_client_id
{
    my ($registryClientName) = @_;

    print("### Getting registry client ID for name [$registryClientName]...\n");

    my $cmd = "$PROGRAM_BIN nifi list-reg-clients -u $NIFI_URL | grep $registryClientName";
    my $line = execute_cmd($cmd, 1);

    if ($line eq '')
    {
        return '';
    }

    # Suppose to get only 1 line here
    my ($no, $name, $id, $uri) = ($line =~ m/^(.+?)\s+(.+?)\s+(.+?)\s+(.+?)\s+$/);

    return $id;
}

sub import_flow_version
{
    my ($flowId, $fileName) = @_;

    print("### Importing flow [$FLOW_NAME] from file [$fileName]...\n");

    my $cmd = "$PROGRAM_BIN registry import-flow-version -u $REGISTRY_URL --flowIdentifier $flowId --input $fileName";
    my $json = execute_cmd($cmd);
}

sub get_flow_id
{
    my ($bucketId, $flowName) = @_;

    print("### Getting flow ID for bucket [$bucketId] --> flow [$flowName]...\n");

    my $cmd = "$PROGRAM_BIN registry list-flows -u $REGISTRY_URL --bucketIdentifier $bucketId -ot json";
    my $json = execute_cmd($cmd);

    my $decoded = decode_json($json);
    my $id = get_id('name', $flowName, 'identifier', $decoded);

    return $id;
}

sub create_flow
{
    my ($bucketId, $flowName) = @_;

    print("### Creating flow [$flowName] for bucket [$bucketId]...\n");

    my $cmd = "$PROGRAM_BIN registry create-flow -u $REGISTRY_URL --bucketIdentifier $bucketId --flowName $flowName";
    my $json = execute_cmd($cmd);
}

sub create_bucket
{
    my ($bucketName) = @_;

    print("### Creating bucket [$bucketName]...\n");

    my $cmd = "$PROGRAM_BIN registry create-bucket -u $REGISTRY_URL --bucketName $bucketName";
    my $json = execute_cmd($cmd);
}

sub get_bucket_id
{
    my ($bucketName) = @_;

    print("### Getting ID for bucket [$bucketName]...\n");

    my $cmd = "$PROGRAM_BIN registry list-buckets -u $REGISTRY_URL -ot json";
    my $json = execute_cmd($cmd);

    my $decoded = decode_json($json);
    my $id = get_id('name', $bucketName, 'identifier', $decoded);

    return $id;
}

sub get_id
{
    my ($keyField, $keyValue, $idField, $arrPtr) = @_;

    my @arr = @$arrPtr;
    foreach my $item ( @arr )
    {
        my $value = $item->{$keyField};
        my $tmpId = $item->{$idField};

        print("@@@ Key=[$keyField] Value=[$value] Id=[$tmpId]...\n");

        if ($value eq $keyValue)
        {
            return $tmpId;
        }
    }

    return '';
}

sub execute_cmd
{
    my ($cmd, $resumeIfError) = @_;

    if (!defined($resumeIfError))
    {
        $resumeIfError = 0;
    }

    my $output = `$cmd`;
    if ($?) 
    {
        if ($resumeIfError != 1)
        {
            # Error here
            print("Error from [$cmd]!!!\n");
            print("$output\n");

            exit($? >> 8);
        }
    }

    return $output;
}