# USNJBackupQueue
## Overview
This script is a reworking/combination of the UsnJrnl2Csv and MftRef2Name tools created by Joakim Schicht (https://github.com/jschicht).

The basic idea is to, after enabling the USN Journal (https://en.wikipedia.org/wiki/USN_Journal) on an NTFS volume, use this tool to extract a list of files that the journal records as having been changed.  You then pass this list of changed files to your backup program (e.g. rsync --include-from=) so that it only backs up these files.

Yes, rsync only copies files that have been changed by default, the problem arises however that if you have millions of files with only a limited subset of them changing, rsync will still spend a lot of time checking meta-data and checksums to work out what has changed.  Using this tool allows rsync to skip this check.

So you don't repeat the mistake I made, because this is a console script, you can't simply double click the .au3 file or run "AutoIt3.exe FileName.au3" to use it.  You won't get any output.  You need to either compile the script into an executable using Aut2exe.exe with the "/console" switch or run this script from within the AutoIt3 provided SciTE-Lite editor.

Finally, my excuse for code in this script being ugly and inefficient is that this is the first time I have ever worked with AutoIt code and there are large portions of Joakim's code that I don't fully understand.  Sorry.

## Limitations
### Incomplete
Not all of the basics are connected up and operating yet.  It's close to being a functional prototype.

### Performance
The functions used to translate $Mft references into full file names were written by the original author to run once and exit.  I think I can improve performance by adding some caching of lookups that have already been completed so every request doesn't need to work out every step in the parent/child relationship from scratch each time.

For example, if there are 50 changed files in the same directory that is 3 levels deep into the filesystem hierachy (e.g. E:\folder\folder\folder\file1, E:\folder\folder\folder\file2, etc.) then the code as it stands makes 200 lookups (50 files * (3 directory levels + the file itself)) to the $Mft.  If we could cache the $Mft reference for "E:\folder\folder\folder\" though we would only need 54 lookups (4 to resolve "E:\folder\folder\folder\" the first time + 50 for the files themselves).

## Usage
```
  BackupQueueFromUSNJournal.exe [-h|-l|-v|-V] [-m num] Volume
     -h      Show this help message and quit
     -l      Use longer sleep cycles to reduce CPU usage and the expense of the
             process taking longer.  You can use this switch twice to further
             increase the length of the sleep cycles.
     -m num  Specify the USN of the first acceptable journal entry.  This will
             likely be the 'Maximum Found USN' from the previous run.
             Basically, all journal entries before the specified num will be
             ignored as it is assumed that the changes they represent have
             already been captured by previous backup runs.
     -v      Enable verbose output.  Use twice for more verbose output.
     -V      Output version and quit
     Volume  The volume to extract the USN Journal from
```

More doco to come once this project matures a little more.
