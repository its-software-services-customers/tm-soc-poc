#!/bin/perl

use strict;
use warnings;
use JSON qw( decode_json );
no warnings 'utf8';

my $templateDir = "."; #"98-test";

print("#key,found,type\n");

my $ipAttrPtr = get_attributes(read_file_content("$templateDir/misp-ip.json"));
print_lines($ipAttrPtr);

my $domainAttrPtr = get_attributes(read_file_content("$templateDir/misp-domain.json"));
print_lines($domainAttrPtr);

exit(0);

sub get_attributes
{
    my ($content) = @_;
    my $decoded = decode_json($content);
    my $attrPtr = $decoded->{'response'}->{'Attribute'};

    return $attrPtr;
}

sub print_lines
{
    my ($arrPtr) = @_;
    my @attributes = @$arrPtr;

    foreach my $attr ( @attributes )
    {
        my $key = $attr->{'value'};
        my $type = $attr->{'type'};
        my $found = 1;

        print("$key,$found,$type\n");
    }    
}

sub read_file_content
{
    my ($fname) = @_;

    open my $fh, '<', "$fname" or die "Can't open file [$fname] [$!]";
    my $file_content = do { local $/; <$fh> };
    close($fh);

    return $file_content;
}