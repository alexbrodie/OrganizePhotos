# NAME

OrganizePhotos - utilities for managing a collection of photos/videos

# SYNOPSIS

    OrganizePhotos -h
    OrganizePhotos check-md5|c5 [--add-only] [glob patterns...]
    OrganizePhotos checkup|c [--add-only] [--auto-diff|-d] [--by-name|-n]
        [--no-default-last-action] [glob patterns...]
    OrganizePhotos collect-trash|ct [glob patterns...]
    OrganizePhotos find-dupe-files|fdf [--auto-diff|-d] [--by-name|-n]
        [--no-default-last-action] [glob-patterns...]
    OrganizePhotos metadata-diff|md [--exclude-sidecars|-x] [glob-patterns...]
    OrganizePhotos remove-empties|re [glob-patterns...]
    OrganizePhotos restore-trash|rt [glob-patterns...]

# DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.

Metadata this program needs to persist are stored in database files in
the same directory as the files that data was generated for. If they 
are separated, the metadata will no longer be associated and the separated
media files will be treated as new. The expectation is that if files move,
the per-directory database file is also moved or copied.

Metadata operations are powered by [`Image::ExifTool`](https://metacpan.org/pod/Image%3A%3AExifTool).

The calling pattern for each command follows the pattern:

    OrganizePhotos <verb> [options...]

Options are managed with [`Getopt::Long`](https://metacpan.org/pod/Getopt%3A%3ALong), and thus may appear anywhere
after the verb, with remaining arguments being used as input for the verb.
Most verbs' non-option arguments are glob patterns describing which files
to operate on.

The following verbs are available:

## **`check-md5`** _(`c5`)_

For each media file under the current directory, generate the MD5 hash
and either add to the database if missing or verify hashes match if
already present.

This method is read/write for per-directory database files. If you want
to perform read-only MD5 checks (i.e., don't write to the database), 
then use the `verify-md5` verb.

This does not modify media files or their sidecars, it only modifies
the per-directory database files.

### Options & Arguments

- **`--add-only`**

    Only operate on files that haven't had their MD5 computed and stored
    yet. This option means that no existing MD5s will be verified.

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern(s).

### Examples

    # Check or add MD5 for several types of video files in the
    # current directory
    $ OrganizePhotos c5 *.mp4 *.m4v *.mov

## **`checkup`** _(`c`)_

This command runs the following suggested suite of commands:

    check-md5
    find-dupe-files
    remove-empties
    collect-trash

### Options & Arguments

- **`-d`**, **`--auto-diff`**

    Automatically do the `d` diff command for every new group of files

- **`--no-default-last-action`**

    Don't use the last action as the default action (what is used if an
    empty command is specified, i.e. you just press Enter). Enter without
    entering a command will re-prompt.

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern(s).

### Examples

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

## **`collect-trash`** _(`ct`)_

Looks recursively for `.orphtrash` subdirectories under the current directory
and moves that content to the current directory's `.orphtrash` perserving
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

### Options & Arguments

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern(s).

### Examples

    # Collect trash in directories starting with Do, e.g.
    # Documents/.orphtrash, Downloads/.orphtrash, etc.
    $ OrganizePhotos ct Do*

## **`find-dupe-files`** _(`fdf`)_

Find files that have multiple copies under the current directory,
and walks through a series of interactive prompts for resolution.

### Options & Arguments

- **`-d`**, **`--auto-diff`** 

    Automatically do the `d` diff command for every new group of files

- **`--no-default-last-action`**

    Don't use the last action as the default action (what is used if an
    empty command is specified, i.e. you just press Enter). Enter without
    entering a command will re-prompt.

- **`-n`**, **`--by-name`**

    Search for duplicates based on name rather than the default of MD5

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern(s).

### Examples

    # Find duplicate files across Alpha and Bravo directories
    $ OrganizePhotos fdf Alpha Bravo

## **`metadata-diff`** _(`md`)_

Do a diff of the specified media files (including their sidecar metadata).

This method does not modify any file.

### Options & Arguments

- **`-x`**, **`--exclude-sidecars`**

    Don't include sidecar metadata for a file. For example, a CR2 file wouldn't 
    include any metadata from a sidecar XMP which typically is the place where
    user added tags like rating and keywords are placed.

- **files**

    Specifies which files to diff

### Examples

    # Do a three way diff between the metadata in the JPGs
    $ OrganizePhotos md one.jpg two.jpg three.jpg

## **`remove-empties`** _(`re`)_

Trash any subdirectories that are empty except for disposable files.
Disposable files include .DS\_Store, thumbs.db, and our per-directory
database files.

### Options & Arguments

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern(s).

### Examples

    # Removes empty directories that are descendants of directories
    # in the current directory that have 'abc' in their name
    $ OrganizePhotos re *abc*

## **`restore-trash`** _(`rt`)_

Put any trash generated by this app back

### Options & Arguments

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern(s).

### Examples

    # Restores all trash under the Foo directory
    $ OrganizePhotos rt Foo

## **`verify-md5`** _(`v5`)_

Verifies the MD5 hashes for all contents of all database files below
the current directory.

This method is read-only, if you want to add/update MD5s, use `check-md5`.

This method does not modify any file.

### Options & Arguments

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern(s).

### Examples

    # Verifies the MD5 for all MP4 files in the current directory
    $ OrganizePhotos v5 *.mp4

# AUTHOR

Copyright 2017, Alex Brodie

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

# SEE ALSO

- [`Image::ExifTool`](https://metacpan.org/pod/Image%3A%3AExifTool)
- [`Getopt::Long`](https://metacpan.org/pod/Getopt%3A%3ALong)
