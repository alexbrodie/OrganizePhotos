@perl -x "%~f0" %*
@goto :EOF
#!perl
#line 5

# Checks and/or generates MD5 hashes for files
#
# MD5 hashes are stored in a md5.txt file in the file's directory with
# one line per file with the pattern
# filename: hash
#
# Usage:
#
# CheckMd5
#   Verifies the MD5 hashes for all contents of all md5.txt files below
#   the current directory
#
# CheckMd5 glob_pattern
#   For each file matching glob_pattern, generate the MD5 hash and either
#   add to md5.txt file if missing or verify hashes match if already present

use strict;
use warnings;

use Carp qw(confess);
use File::Find;

# What we expect an MD5 hash to look like
my $md5pattern = qr/[0-9a-fA-F]{32}/;

main();
exit 0;

#--------------------------------------------------------------------------
sub main {
    if ($#ARGV == -1) {
        # Verify the contents of all the md5.txt files
        find(\&verifyMd5Files, '.');
    } else {
        # Write out MD5s for all the specified files
        processFile($_) for sort map { glob } @ARGV;
    }
}

#--------------------------------------------------------------------------
sub verifyMd5Files {
    if ($_ eq 'md5.txt') {
        open(my $fh, '<', $_) or die "Couldn't open $File::Find::name: $!";
        my $md5s = readMd5File($fh);
        
        for (sort keys %$md5s) {
            verifyMd5($File::Find::dir . '/' . $_, $md5s->{$_});
        }
    }
}

#--------------------------------------------------------------------------
sub processFile {
    my ($filename) = @_;

    # The filename that contains the MD5 info
    (my $md5File = $filename) =~ s/[^\\\/]+$/md5.txt/;
    
    # Open MD5 file    
    my $fh;
    my $md5s;
    if (open($fh, '+<', $md5File)) {
        # Read existing contents
        $md5s = readMd5File($fh);
    } else {
        # File doesn't exist, open for write
        open($fh, '>', $md5File) or confess "Couldn't open $md5File: $!";
    }

    # Try lookup into MD5 file contents
    $filename =~ /([^\\\/]+)$/ or die "couldn't find filename from $filename";
    my $key = lc $1;
    my $expectedMd5 = $md5s->{$key};
    if ($expectedMd5) {
        verifyMd5($filename, $expectedMd5, $actualMd5);
    } else {
        # Wasn't there - new file
        $md5s->{$key} = getMd5($filename);
        trace('Added MD5 for ', $filename);

        # Clear MD5 file
        seek($fh, 0, 0);
        truncate($fh, 0);
    
        # Update MD5 file
        for (sort keys %$md5s) {
            print $fh lc $_, ': ', $md5s->{$_}, "\n";
        }
    }
}

#--------------------------------------------------------------------------
sub readMd5File {
    my ($fh) = @_;

    my %md5s = ();
    for (<$fh>) {
        chomp;
        /^([^:]+):\s*($md5pattern)$/ or die "unexpected line in MD5: $_";
        $md5s{lc $1} = $2;
    }

    return \%md5s;
}

#--------------------------------------------------------------------------
sub verifyMd5 {
    my ($filename, $expectedMd5) = @_;

    my $actualMd5 = getMd5($filename);

    if ($expectedMd5 eq $actualMd5) {
        trace('Verified MD5 for ', $filename);
        return;
    }

    my $error = "ERROR: MD5 mismatch for $filename\n" .
        "actual:   $actualMd5\n" .
        "expected: $expectedMd5\n";

    our $all;
    unless ($all) {
        while (1) {
            print "Continue? [y/n/a]";
            chomp(my $in = <STDIN>);

            last if $in =~ /^y$/i;
            ($all = 1) and last if $in =~ /^a$/i;
            die $error if $in =~ /^n$/i;
        }
    }
}

#--------------------------------------------------------------------------
# Calculates and returns the MD5 digest of a (set of) file(s)
sub getMd5 {
    use Digest::MD5;

    my $md5 = Digest::MD5->new;

    for (@_) {
        open(my $fh, '<', $_) or confess "Couldn't open $_: $!";
	    binmode $fh;

        #my $modified = formatDate((stat($fh))[9]);
        #print "Date modified: $modified\n";

        $md5->addfile($fh);
    }

    my $hexdigest = $md5->hexdigest; 
    $hexdigest =~ /$md5pattern/ or die "unexpected MD5: $hexdigest";

    return $hexdigest;
}

#--------------------------------------------------------------------------
sub formatDate {
    my ($sec, $min, $hour, $day, $mon, $year) = localtime $_[0];
    return sprintf '%04d-%02d-%02dT%02d:%02d:%02d', 
                   $year + 1900, $mon + 1, $day, $hour, $min, $sec;
}

#--------------------------------------------------------------------------
sub trace {
    print @_, "\n";
}
