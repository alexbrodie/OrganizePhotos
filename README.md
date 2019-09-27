# NAME

OrganizePhotos - utilities for managing a collection of photos/videos

# SYNOPSIS

    # Help:
    OrganizePhotos.pl -h

    # Typical workflow:
    # Import via Image Capture to local folder as originals (unmodified copy)
    # Import that folder in Lightroom as move
    OrganizePhotos.pl checkup /photos/root/dir
    # Archive /photos/root/dir (see help)

# DESCRIPTION

Helps to manage a collection of photos and videos that are primarily
managed by Adobe Lightroom. This helps with tasks not covered by
Lightroom such as: backup/archive, integrity checks, consolidation,
and other OCD metadata organization.

MD5 hashes are stored in a md5.txt file in the file's one line per file
with the pattern:

    filename: hash

Metadata operations are powered by Image::ExifTool.

The calling pattern for each command follows the pattern:

    OrganizePhotos.pl <verb> [options...]

The following verbs are available:

- **add-md5** \[glob patterns...\]
- **append-metadata** &lt;target file> &lt;source files...>
- **check-md5** \[glob patterns...\]
- **checkup** \[-a\] \[-d\] \[-l\] \[-n\] \[glob patterns...\]
- **collect-trash** \[glob patterns...\]
- **consolodate-metadata** &lt;dir>
- **find-dupe-dirs**
- **find-dupe-files** \[-a\] \[-d\] \[-l\] \[-n\] \[glob patterns...\]
- **metadata-diff** &lt;files...>
- **remove-empties** \[glob patterns...\]
- **verify-md5** \[glob patterns...\]

## add-md5 \[glob patterns...\]

_Alias: a5_

For each media file under the current directory that doesn't have a
MD5 computed, generate the MD5 hash and add to md5.txt file.

This does not modify media files or their sidecars, it only adds entries
to the md5.txt files.

### Options

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern.

## check-md5 \[glob patterns...\]

_Alias: c5_

For each media file under the current directory, generate the MD5 hash
and either add to md5.txt file if missing or verify hashes match if
already present.

This method is read/write for MD5s, if you want to perform read-only
MD5 checks (i.e., don't write to md5.txt), then use verify-md5.

This does not modify media files or their sidecars, it only modifies
the md5.txt files.

### Options

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern.

### Examples

    # Check or add MD5 for all CR2 files in the current directory
    $ OrganizePhotos.pl c5 *.CR2

## checkup \[glob patterns...\]

_Alias: c_

This command runs the following suggested suite of commands:

    check-md5 [glob patterns...]
    find-dupe-files [-a | --always-continue] [glob patterns...]
    remove-empties [glob patterns...]
    collect-trash [glob patterns...]

### Options

- **-a, --always-continue**

    Always continue

- **-d, --auto-diff**

    Automatically do the 'd' diff command for every new group of files

- **-l, --default-last-action**

    Enter repeats last command

- **-n, --by-name**

    Search for items based on name rather than the default of MD5

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern.

## collect-trash \[glob patterns...\]

_Alias: ct_

Looks recursively for .Trash subdirectories under the current directory
and moves that content to the current directory's .Trash perserving
directory structure.

For example if we had the following trash:

    ./Foo/.Trash/1.jpg
    ./Foo/.Trash/2.jpg
    ./Bar/.Trash/1.jpg

After collection we would have:

    ./.Trash/Foo/1.jpg
    ./.Trash/Foo/2.jpg
    ./.Trash/Bar/1.jpg

### Options

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern.

## consolodate-metadata &lt;dir>

_Alias: cm_

Not yet implemented

## find-dupe-dirs

_Alias: fdd_

Find directories that represent the same date.

## find-dupe-files \[  patterns...\]

_Alias: fdf_

Find files that have multiple copies under the current directory.

### Options

- **-a, --always-continue**

    Always continue

- **-d, --auto-diff**

    Automatically do the 'd' diff command for every new group of files

- **-l, --default-last-action**

    Enter repeats last command

- **-n, --by-name**

    Search for items based on name rather than the default of MD5

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern.

## metadata-diff &lt;files...>

_Alias: md_

Do a diff of the specified media files (including their sidecar metadata).

This method does not modify any file.

### Options

- **-x, --exclude-sidecars**

    Don't include sidecar metadata for a file. For example, a CR2 file wouldn't 
    include any metadata from a sidecar XMP which typically is the place where
    user added tags like rating and keywords are placed.

## remove-empties \[glob patterns...\]

_Alias: re_

Remove any subdirectories that are empty save an md5.txt file.

### Options

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern.

## verify-md5 \[glob patterns...\]

_Alias: v5_

Verifies the MD5 hashes for all contents of all md5.txt files below
the current directory.

This method is read-only, if you want to add/update MD5s, use check-md5.

This method does not modify any file.

### Options

- **glob patterns**

    Rather than operate on files under the current directory, operate on
    the specified glob pattern.

# Related commands

## Complementary ExifTool commands

    # Append all keyword metadata from SOURCE to DESTINATION
    exiftool -addTagsfromfile SOURCE -HierarchicalSubject -Subject DESTINATION

    # Shift all mp4 times, useful when clock on GoPro is reset to 1/1/2015 due to dead battery
    # Format is: offset='[y:m:d ]h:m:s' or more see https://sno.phy.queensu.ca/~phil/exiftool/Shift.html#SHIFT-STRING
    offset='4:6:24 13:0:0'
    exiftool "-CreateDate+=$offset" "-ModifyDate+=$offset" 
             "-TrackCreateDate+=$offset" "-TrackModifyDate+=$offset" 
             "-MediaCreateDate+=$offset" "-MediaModifyDate+=$offset" *.mp4
    

## Complementary Mac commands

    # Mirror SOURCE to TARGET
    rsync -ah --delete --delete-during --compress-level=0 --inplace --progress 
        SOURCE TARGET

    # Move .Trash directories recursively to the trash
    find . -type d -iname '.Trash' -exec trash {} \;

    # Delete .DS_Store recursively (omit "-delete" to only print)
    find . -type f -name .DS_Store -print -delete

    # Delete zero byte md5.txt files (omit "-delete" to only print)
    find . -type f -iname md5.txt -empty -print -delete

    # Remove empty directories (omit "-delete" to only print)
    find . -type d -empty -print -delete

    # Remove the executable bit for media files
    find . -type f -perm +111 \( -iname "*.CRW" -or -iname "*.CR2"
        -or -iname "*.JPEG" -or -iname "*.JPG" -or -iname "*.M4V"
        -or -iname "*.MOV" -or -iname "*.MP4" -or -iname "*.MPG"
        -or -iname "*.MTS" -or -iname "*.NEF" -or -iname "*.RAF"
        -or -iname "md5.txt" \) -print -exec chmod -x {} \;

    # Remove downloaded-and-untrusted extended attribute for the current tree
    xattr -d -r com.apple.quarantine .

    # Find large-ish files
    find . -size +100MB

    # Display disk usage stats sorted by size decreasing
    du *|sort -rn

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

## Complementary PC commands

    # Mirror SOURCE to TARGET
    robocopy /MIR SOURCE TARGET

# AUTHOR

Copyright 2017, Alex Brodie

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

# SEE ALSO

[Image::ExifTool](https://metacpan.org/pod/Image::ExifTool)
