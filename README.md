# USNJBackupQueue
## Overview
This script is a reworking/combination of the UsnJrnl2Csv and MftRef2Name tools created by Joakim Schicht (https://github.com/jschicht).

The basic idea is to, after enabling the USN Journal (https://en.wikipedia.org/wiki/USN_Journal) on an NTFS volume, use this tool to extract a list of files that the journal records as having been changed.  You then pass this list of changed files to your backup program (e.g. rsync --include-from=) so that it only backs up these files.

Yes, rsync only copies files that have been changed by default, the problem arises however that if you have millions of files with only a limited subset of them changing, rsync will still spend a lot of time checking meta-data and checksums to work out what has changed.  Using this tool allows rsync to skip this check.

So you don't repeat the mistake I made, because this is a console script, you can't simply double click the .au3 file or run "AutoIt3.exe FileName.au3" to use it.  You won't get any output.  You need to either compile the script into an executable using Aut2exe.exe with the "/console" switch or run this script from within the AutoIt3 provided SciTE-Lite editor.

To create a stand alone executable:
```
"C:\Program Files (x86)\AutoIt3\Aut2Exe\Aut2exe_x64.exe" /in BackupQueueFromUSNJournal.au3 /console /fileversion 1.0.0.4 /productversion 1.0.0.4 /productname BackupQueueFromUSNJournal
```

Finally, my excuse for code in this script being ugly and inefficient is that this is the first time I have ever worked with AutoIt code and there are large portions of Joakim's code that I don't fully understand.  Sorry.

## Limitations
### Completeness
Every feature in the Usage section below has been implemented, except the time limit (-t).

### Testing
I haven't extensively tested every feature and function yet but it passes all of the basic functionality tests I have thrown at it so far with my test systems.

### Performance
The functions used to translate $Mft references into full file names were written by the original author to run once and exit so they are possibly not as efficient fo multiple lookups as they could be.  I have worked around the latency that these lookups take by caching every lookup we already know the answer to (from previous lookups and from the USN Journal itself).

I have recently added some code that skips journal pages if it KNOWS the "first acceptable journal entry" (-m) is not going to be in those pages.  In cases where the journal is very large but contains mostly entries that are older than the "first acceptable journal entry" (because they were processed on a previous occasion) this greatly reduces processing time.

## Experimental "Run as a service" mode
I have begun working on a feature to have the application running constantly in the background, periodically processing the USN Journal.  The general idea being that instead of processing a large amount of journal entries at backup time, the process happens frequently processing the journal entries in smaller batches.  It's too early to tell if this will be a useful feature or a dead end.

Other than the smaller batches, this method caches the results of the slow $Mft lookups so if the same file changes multiple times during the day (the caches are purged every 24 hours for safety) the slow $Mft lookup will only happen for the first change.

## Some default options stored in the registry
To better support the Experimental "Run as a service" mode, some options that would normally be specified on the command line can now be set in the registry.  Command line options override the values specified in the registry.

I'll document the available options in the future.  In the mean time you can see the option names and where in the registry they are loaded from by looking at the ```_LoadConfigFromRegistry``` function in ```BackupQueueFromUSNJournal.au3```.

## Usage
```
BackupQueueFromUSNJournal 1.0.0.4

  BackupQueueFromUSNJournal.exe [-h|-l|-v|-V] [-m num] [-a file|-o file] Volume
     -a file Append changed file list to file.
     -h      Show this help message and quit
     -l      Use longer sleep cycles to reduce CPU usage and the expense of the
             process taking longer.  You can use this switch twice or three
             times to further increase the length of the sleep cycles.
     -m num  Specify the USN of the first acceptable journal entry.  This will
             likely be the 'Maximum Found USN' from the previous run.
             Basically, all journal entries before the specified num will be
             ignored as it is assumed that the changes they represent have
             already been captured by previous backup runs.  If unspecified
             the lowest numbered journal entry is used.
     -M num  Maximum number of jounal entries between the first acceptable
             entry (see '-m' above) and the last entry in the journal. If there
             are more than num entries, abort and suggest running a full backup
             Not yet implemented.
     -o file Output changed file list to file.  If file already exists it will
             be overwritten
     +p      Include the parent directories of each object in the output list.
     -p      Do not include the parent directories of each object in the output

             list.
     -r      Output file paths relative to the volume root.
     -R path Output file paths relative to the volume root and prefixed with
             path.  This might be useful if you want to create a full path in
             UNC format or reference a VSS snapshot via
             \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopyXXX
     -service Start BackupQueueFromUSNJournal in the experimental 'run as a
             servce' mode
     -S      Exclude files in the 'System Volume Information' directory.
     +S      Include files in the 'System Volume Information' directory.
     -T      Exclude files in the '$RECYCLE.BIN' directory.
     +T      Include files in the '$RECYCLE.BIN' directory.
     -t sec  Time limit.  Don't spend more the sec seconds extracting values
             before aborting and suggesting a full backup instead.  Not yet
             implemented.
     +u      Use Unix (/) instead of Windows (\) path separator.
     -u      Use Windows (\) instead of Unix (/) path separator.
     -v      Enable verbose output.  Use twice for more verbose output.
     -V      Output version and quit
     Volume  The volume to extract the USN Journal from
```

More doco to come once this project matures a little more.
