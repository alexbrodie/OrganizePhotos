#!/usr/bin/perl

use strict;
use warnings;
use warnings FATAL => qw(uninitialized);

# Enable local lib
use File::Basename;
use Cwd qw(abs_path);
use lib dirname(abs_path(__FILE__));

# Local uses
use OrganizePhotos;
use View;

# Library uses
use Carp;
$SIG{__DIE__} =  \&Carp::confess;
$SIG{__WARN__} = \&Carp::cluck;
use Getopt::Long ();
BEGIN { $Pod::Usage::Formatter = 'Pod::Text::Termcap'; }
use Pod::Usage ();

sub myGetOptions {
    my $filter = undef;
    my %flags = (   'verbosity|v:+' => \$View::Verbosity,
                    'filter|f=s' => \$filter, 
                    @_ );
    Getopt::Long::GetOptions(%flags) or die "Error in command line, aborting.";

    my $msg = "Operation arguments:\n";
    for (sort keys %flags) {
        use Data::Dumper;
        local $Data::Dumper::Terse = 1;
        chomp(my $flag_value = Data::Dumper::Dumper(${$flags{$_}}));
        $msg = "$msg\tFlag: $_ => $flag_value\n";
    }
    for (@ARGV) {
        $msg = "$msg\tArgv: '$_'\n";
    }
    print_with_icon('[i]', undef, $msg);

    if ($filter) {
        if ($filter eq 'all') {
            $OrganizePhotos::filenameFilter = qr//;
        } elsif ($filter eq 'media') {
            $OrganizePhotos::filenameFilter = $FileTypes::MEDIA_TYPE_FILENAME_FILTER;
        } elsif ($filter =~ /^qr(.*)$/) {
            $OrganizePhotos::filenameFilter = qr/$1/;
        } elsif ($filter =~ /^\.(.*)$/) {
            $OrganizePhotos::filenameFilter = qr/\.(?i)(?:@{[ join '|', split '\.', $1 ]})$/;
        } else {
            die "Unknown filter '$filter', choose from all, media, .ext.ex2.etc, qrREGEXP\n";
        }
        trace(View::VERBOSITY_LOW, "Filter set to: ", $OrganizePhotos::filenameFilter);
    }
    return @ARGV;
}

# Parse args (using GetOptions) and delegate to the doVerb methods...
unless (@ARGV) {
    Pod::Usage::pod2usage();
} elsif ($#ARGV == 0 and $ARGV[0] =~ /^-[?h]|help$/i) {
    Pod::Usage::pod2usage(-verbose => 2);
} else {
    Getopt::Long::Configure('bundling');
    my $verb = shift @ARGV;
    if ($verb eq 'append-metadata' or $verb eq 'am') {
        my @args = myGetOptions();
        doAppendMetadata(@args);
    } elsif ($verb eq 'check-md5' or $verb eq 'c5') {
        my $addOnly = 0;
        my $forceRecalc = 0;
        my @args = myGetOptions(
            'add-only' => \$addOnly,
            'force-recalc' => \$forceRecalc);
        doCheckMd5($addOnly, $forceRecalc, @args);
    } elsif ($verb eq 'checkup' or $verb eq 'c') {
        my $addOnly = 0;
        my $autoDiff = 0;
        my $byName = 0;
        my $forceRecalc = 0;
        my $noDefaultLastAction = 0;
        my @args = myGetOptions(
            'add-only' => \$addOnly,
            'auto-diff|d' => \$autoDiff,
            'by-name|n' => \$byName,
            'no-default-last-action' => \$noDefaultLastAction);
        doCheckMd5($addOnly, $forceRecalc, @args);
        #doPurgeMd5(@args);
        doFindDupeFiles($byName, $autoDiff, 
                        !$noDefaultLastAction, @args);
        doRemoveEmpties(@args);
        doCollectTrash(@args);
    } elsif ($verb eq 'collect-trash' or $verb eq 'ct') {
        my @args = myGetOptions();
        doCollectTrash(@args);
    } elsif ($verb eq 'find-dupe-dirs' or $verb eq 'fdd') {
        my @args = myGetOptions();
        @args and die "Unexpected parameters: @args\n";
        doFindDupeDirs();
    } elsif ($verb eq 'find-dupe-files' or $verb eq 'fdf') {
        my $autoDiff = 0;
        my $byName = 0;
        my $noDefaultLastAction = 0;
        my @args = myGetOptions(
            'auto-diff|d' => \$autoDiff,
            'by-name|n' => \$byName,
            'no-default-last-action' => \$noDefaultLastAction);
        doFindDupeFiles($byName, $autoDiff, 
                        !$noDefaultLastAction, @args);
    } elsif ($verb eq 'metadata-diff' or $verb eq 'md') {
        my $excludeSidecars = 0;
        my @args = myGetOptions(
            'exclude-sidecars|x' => \$excludeSidecars);
        do_metadata_diff(0, $excludeSidecars, @args);
    } elsif ($verb eq 'purge-md5' or $verb eq 'p5') {
        my @args = myGetOptions();
        doPurgeMd5(@args);
    } elsif ($verb eq 'remove-empties' or $verb eq 're') {
        my @args = myGetOptions();
        doRemoveEmpties(@args);
    } elsif ($verb eq 'restore-trash' or $verb eq 'rt') {
        my @args = myGetOptions();
        doRestoreTrash(@args);
    } elsif ($verb eq 'test') {
        my @args = myGetOptions();
        doTest(@args);
    } elsif ($verb eq 'verify-md5' or $verb eq 'v5') {
        my @args = myGetOptions();
        do_verify_md5(@args);
    } else {
        die "Unknown verb: $verb\n";
    }
}

1;

__END__

Commands to regenerate documentation:
  cpanm Pod::Markdown
  pod2markdown OrganizePhotos.pl > README.md

=head1 NAME

OrganizePhotos - utilities for managing a collection of photos/videos

=head1 SYNOPSIS

    OrganizePhotos -h
    OrganizePhotos check-md5|c5 [--add-only] [--force-recalc] [glob patterns...]
    OrganizePhotos checkup|c [--add-only] [--auto-diff|-d] [--by-name|-n]
        [--no-default-last-action] [glob patterns...]
    OrganizePhotos collect-trash|ct [glob patterns...]
    OrganizePhotos find-dupe-files|fdf [--auto-diff|-d] [--by-name|-n]
        [--no-default-last-action] [glob-patterns...]
    OrganizePhotos metadata-diff|md [--exclude-sidecars|-x] [glob-patterns...]
    OrganizePhotos purge-md5|p5 [glob-patterns...]
    OrganizePhotos remove-empties|re [glob-patterns...]
    OrganizePhotos restore-trash|rt [glob-patterns...]

=head1 DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.

Metadata this program needs to persist are stored in database files in
the same directory as the files that data was generated for. If they 
are separated, the metadata will no longer be associated and the separated
media files will be treated as new. The expectation is that if files move,
the per-directory database file is also moved or copied.

Metadata operations are powered by L<C<Image::ExifTool>>.

The calling pattern for each command follows the pattern:

    OrganizePhotos <verb> [options...]

Options are managed with L<C<Getopt::Long>>, and thus may appear anywhere
after the verb, with remaining arguments being used as input for the verb.
Most verbs' non-option arguments are glob patterns describing which files
to operate on.

The following verbs are available:

=head2 B<C<check-md5>> I<(C<c5>)>

For each media file under the current directory, generate the MD5 hash
and either add to the database if missing or verify hashes match if
already present.

This method is read/write for per-directory database files. If you want
to perform read-only MD5 checks (i.e., don't write to the database), 
then use the C<verify-md5> verb.

This does not modify media files or their sidecars, it only modifies
the per-directory database files.

=head3 Options & Arguments

=over 24

=item B<C<--add-only>>

Only operate on files that haven't had their MD5 computed and stored
yet. This option means that no existing MD5s will be verified.

=item B<C<--force-recalc>>

Forces a recalc of file even if cached data is up to date. Updates
the cache with the new data.

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Check or add MD5 for several types of video files in the
    # current directory
    $ OrganizePhotos c5 *.mp4 *.m4v *.mov

=head2 B<C<checkup>> I<(C<c>)>

This command runs the following suggested suite of commands:

    check-md5 [--add-only] [glob patterns]
    find-dupe-files [--auto-diff|d] [--by-name|n]
        [--no-default-last-action] [glob patterns]
    remove-empties [glob patterns]
    collect-trash [glob patterns]

=head3 Options & Arguments

=over 24

=item B<C<--add-only>>

Only operate on files that haven't had their MD5 computed and stored
yet. This option means that no existing MD5s will be verified.

=item B<C<-d>>, B<C<--auto-diff>>

Automatically do the C<d> diff command for every new group of files

=item B<C<--no-default-last-action>>

Don't use the last action as the default action (what is used if an
empty command is specified, i.e. you just press Enter). Enter without
entering a command will re-prompt.

=item B<C<-n>>, B<C<--by-name>>

Search for duplicates based on name rather than the default of MD5.

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Performs a checkup of directory foo doing auto-diff during
    # the find-dupe-files phase
    $ OrganizePhotos c foo -d

    # These next 4 together are equivalent to the previous statement 
    $ OrganizePhotos c5 foo
    $ OrganizePhotos fdf --auto-diff foo 
    $ OrganizePhotos re foo
    $ OrganizePhotos ct foo

    # Find all the duplicate windows binaries under the bin dir
    $ OrganizePhotos c -fqr"\.(?:(?i)dll|exe|scr)$" bin

=head2 B<C<collect-trash>> I<(C<ct>)>

Looks recursively for C<.orphtrash> subdirectories under the current directory
and moves that content to the current directory's C<.orphtrash> perserving
directory structure.

For example if we had the following trash:

    ./Foo/.orphtrash/1.jpg
    ./Foo/.orphtrash/2.jpg
    ./Bar/.orphtrash/3.jpg
    ./Bar/Baz/.orphtrash/4.jpg

After collection we would have:

    ./.orphtrash/Foo/1.jpg
    ./.orphtrash/Foo/2.jpg
    ./.orphtrash/Bar/3.jpg
    ./.orphtrash/Bar/Baz/4.jpg

=head3 Options & Arguments

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Collect trash in directories starting with Do, e.g.
    # Documents/.orphtrash, Downloads/.orphtrash, etc.
    $ OrganizePhotos ct Do*

=head2 B<C<find-dupe-files>> I<(C<fdf>)>

Find files that have multiple copies under the current directory,
and walks through a series of interactive prompts for resolution.

=head3 Options & Arguments

=over 24

=item B<C<-d>>, B<C<--auto-diff>> 

Automatically do the C<d> diff command for every new group of files

=item B<C<--no-default-last-action>>

Don't use the last action as the default action (what is used if an
empty command is specified, i.e. you just press Enter). Enter without
entering a command will re-prompt.

=item B<C<-n>>, B<C<--by-name>>

Search for duplicates based on name rather than the default of MD5.

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Find duplicate files across Alpha and Bravo directories
    $ OrganizePhotos fdf Alpha Bravo

=head2 B<C<metadata-diff>> I<(C<md>)>

Do a diff of the specified media files (including their sidecar metadata).

This method does not modify any file.

=head3 Options & Arguments

=over 24

=item B<C<-x>>, B<C<--exclude-sidecars>>

Don't include sidecar metadata for a file. For example, a CR2 file wouldn't 
include any metadata from a sidecar XMP which typically is the place where
user added tags like rating and keywords are placed.

=item B<files>

Specifies which files to diff

=back

=head3 Examples

    # Do a three way diff between the metadata in the JPGs
    $ OrganizePhotos md one.jpg two.jpg three.jpg

=head2 B<C<purge-md5>> I<(C<p5>)>

Trash database entries that reference files that no longer exist at the
location where they were indexed, presumably because they were moved
or deleted.

=head3 Options & Arguments

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Trash all orphaned MD5 data under the current directory
    $ OrganizePhotos p5

=head2 B<C<remove-empties>> I<(C<re>)>

Trash any subdirectories that are empty except for disposable files.
Disposable files include .DS_Store, thumbs.db, and our per-directory
database files.

=head3 Options & Arguments

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Removes empty directories that are descendants of directories
    # in the current directory that have 'abc' in their name
    $ OrganizePhotos re *abc*

=head2 B<C<restore-trash>> I<(C<rt>)>

Put any trash generated by this app back

=head3 Options & Arguments

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Restores all trash under the Foo directory
    $ OrganizePhotos rt Foo

=head2 B<C<verify-md5>> I<(C<v5>)>

Verifies the MD5 hashes for all contents of all database files below
the current directory.

This method is read-only, if you want to add/update MD5s, use C<check-md5>.

This method does not modify any file.

=head3 Options & Arguments

=over 24

=item B<glob patterns>

Rather than operate on files under the current directory, operate on
the specified glob pattern(s).

=back

=head3 Examples

    # Verifies the MD5 for all MP4 files in the current directory
    $ OrganizePhotos v5 *.mp4

=begin comment

=head1 TODO

=head2 AppendMetadata

Find files that aren't in a directory appropriate for their date

=head2 FindMisplacedFiles

Find files that aren't in a directory appropriate for their date

=head2 FindDupeFolders

Find the folders that represent the same date

=head2 FindMissingFiles

Finds files that may be missing based on gaps in sequential photos

=head2 FindScreenShots

Find files which are screenshots

=head2 FindOrphanedFiles

Find XMP or THM files that don't have a cooresponding main file

=head2 --if-modified-since

Flag for CheckMd5/VerifyMd5 to only check files created/modified since
the provided timestamp or timestamp at last MD5 check

=head1 Related commands

=head2 Complementary ExifTool commands

    # Append all keyword metadata from SOURCE to DESTINATION
    exiftool -addTagsfromfile SOURCE -HierarchicalSubject -Subject DESTINATION

    # Shift all mp4 times, useful when clock on GoPro is reset to 1/1/2015 due to dead battery
    # Format is: offset='[y:m:d ]h:m:s' or more see https://sno.phy.queensu.ca/~phil/exiftool/Shift.html#SHIFT-STRING
    offset='4:6:24 13:0:0'
    exiftool "-CreateDate+=$offset" "-MediaCreateDate+=$offset" "-MediaModifyDate+=$offset" "-ModifyDate+=$offset" "-TrackCreateDate+=$offset" "-TrackModifyDate+=$offset" *.MP4 

=head2 Complementary Mac commands

    # Mirror SOURCE to TARGET
    rsync -ah --delete --delete-during --compress-level=0 --inplace --progress SOURCE TARGET

    # Make all md5.txt files writable
    find . -type f -name md5.txt -print -exec chflags nouchg {} \;

    # Move all AAE and LRV files in the ToImport folder to trash
    find ~/Pictures/ToImport/ -type f -iname '*.AAE' -or -iname '*.LRV' -exec trash {} \;

    # Delete .DS_Store recursively (omit "-delete" to only print)
    find . -type f -name .DS_Store -print -delete

    # Delete zero byte md5.txt files (omit "-delete" to only print)
    find . -type f -iname md5.txt -empty -print -delete

    # Rename all md5.txt files to .orphdat
    find . -type f -iname md5.txt -exec zsh -c 'mv -v $1 ${1:h}/.orphdat' _ {} \;

    # Remove empty directories (omit "-delete" to only print)
    find . -type d -empty -print -delete

    # Remove the executable bit for media files
    find . -type f -perm +111 \( -iname "*.CRW" -or -iname "*.CR2"
        -or -iname "*.JPEG" -or -iname "*.JPG" -or -iname "*.M4V"
        -or -iname "*.MOV" -or -iname "*.MP4" -or -iname "*.MPG"
        -or -iname "*.MTS" -or -iname "*.NEF" -or -iname "*.RAF"
        \) -print -exec chmod -x {} \;

    # Remove downloaded-and-untrusted extended attribute for the current tree
    xattr -d -r com.apple.quarantine .

    # Find large-ish files
    find . -size +100MB

    # Display disk usage stats sorted by size decreasing
    du *|sort -rn

    # Find all HEIC files that have a JPG with the same base name
    find . -iname '*.heic' -execdir sh -c 'x="{}"; y=${x:0:${#x}-4}; [[ -n `find . -iname "${y}jpg"` ]] && echo "$PWD/$x"' \;

    # For each HEIC move some metadata from neighboring JPG to XMP sidecar
    # and trash the JPG. This is useful when you have both the raw HEIC from
    # iPhone and the converted JPG which holds the metadata and you want to
    # move it to the HEIC and just keep that. For example if you import once
    # as JPG, add metadata, and then re-import as HEIC.
    find . -iname '*.heic' -exec sh -c 'x="{}"; y=${x:0:${#x}-4}; exiftool -tagsFromFile ${y}jpg -Rating -Subject -HierarchicalSubject ${y}xmp; trash ${y}jpg' \;

    # For each small MOV file, look for pairing JPG or HEIC files and print
    # the path of the MOV files where the main image file is missing.
    find . -iname '*.mov' -size -6M -execdir sh -c 'x="{}"; y=${x:0:${#x}-3}; [[ -n `find . -iname "${y}jpg" -o -iname "${y}heic"` ]] || echo "$PWD/$x"' \;

    # Restore _original files (undo exiftool changes)
    find . -iname '*_original' -exec sh -c 'x={}; y=${x:0:${#x}-9}; echo mv $x $y' \;

=head2 Complementary PC commands

    # Mirror SOURCE to TARGET
    robocopy /MIR SOURCE TARGET

=head3 Complementary cross platform commands

    # Strip YYYY-MM-DD- prefix from filenames
    perl -MFile::Copy -e 'for (@ARGV) { /^\d{4}-\d\d-\d\d-(.*)/ and move($_, $1) }' * 

=end comment

=head1 AUTHOR

Copyright 2017, Alex Brodie

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

=over

=item L<C<Image::ExifTool>>

=item L<C<Getopt::Long>>

=back

=cut
