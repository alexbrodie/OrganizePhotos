# NAME

OrganizePhotos - utilities for managing a collection of photos/videos

# SYNOPSIS

    # Get help
    $ OrganizePhotos -h

    # Run checkup on a directory
    $ OrganizePhotos c /photos/root/dir

# DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.

Metadata this program needs to persist are stored in `md5.txt` files in
the same directory as the files that data was generated for. If they 
are separated, the metadata will no longer be associated and the separated
media files will be treated as new. The expectation is that if files move,
the `md5.txt` file is also moved or copied.

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
and either add to `md5.txt` file if missing or verify hashes match if
already present.

This method is read/write for `md5.txt` files. If you want to perform
read-only MD5 checks (i.e., don't write to `md5.txt`), then use the
`verify-md5` verb.

This does not modify media files or their sidecars, it only modifies
the `md5.txt` files.

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

- **`--auto-diff`** _(`-d`)_

    Automatically do the `d` diff command for every new group of files

- **`--default-last-action`** _(`-l`)_

    Use the last action as the default action (what is used if an
    empty command is specified, i.e. you just press Enter)

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

## **`collect-trash`** _(`ct`)_

Looks recursively for `.Trash` subdirectories under the current directory
and moves that content to the current directory's `.Trash` perserving
directory structure.

For example if we had the following trash:

    ./Foo/.Trash/1.jpg
    ./Foo/.Trash/2.jpg
    ./Bar/.Trash/3.jpg
    ./Bar/Baz/.Trash/4.jpg

After collection we would have:

    ./.Trash/Foo/1.jpg
    ./.Trash/Foo/2.jpg
    ./.Trash/Bar/3.jpg
    ./.Trash/Bar/Baz/4.jpg

### Options & Arguments

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern(s).

### Examples

    # Collect trash in directories starting with Do, e.g.
    # Documents/.Trash, Downloads/.Trash, etc.
    $ OrganizePhotos ct Do*

## **`find-dupe-files`** _(`fdf`)_

Find files that have multiple copies under the current directory,
and walks through a series of interactive prompts for resolution.

### Options & Arguments

- **`--auto-diff`** _(`-d`)_

    Automatically do the `d` diff command for every new group of files

- **`--default-last-action`** _(`-l`)_

    Use the last action as the default action (what is used if an
    empty command is specified, i.e. you just press Enter)

- **`--by-name`** _(`-n`)_

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

- **`--exclude-sidecars`** _(`-x`)_

    Don't include sidecar metadata for a file. For example, a CR2 file wouldn't 
    include any metadata from a sidecar XMP which typically is the place where
    user added tags like rating and keywords are placed.

- **files**

    Specifies which files to diff

### Examples

    # Do a three way diff between the metadata in the JPGs
    $ OrganizePhotos md one.jpg two.jpg three.jpg

## **`remove-empties`** _(`re`)_

Remove any subdirectories that are empty save an `md5.txt` file.

### Options & Arguments

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern(s).

### Examples

    # Removes empty directories that are descendants of directories
    # in the current directory that have 'abc' in their name
    $ OrganizePhotos re *abc*

## **`verify-md5`** _(`v5`)_

Verifies the MD5 hashes for all contents of all `md5.txt` files below
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
