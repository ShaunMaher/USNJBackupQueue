# USNJBackupQueue
## Overview
This script is a reworking/combination of the UsnJrnl2Csv and MftRef2Name tools created by Joakim Schicht (https://github.com/jschicht).

The basic idea is to, after enabling the USN Journal (https://en.wikipedia.org/wiki/USN_Journal) on an NTFS volume, use this tool to extract a list of files that the journal records as having been changed.  You then pass this list of changed files to your backup program (e.g. rsync --include-from=) so that it only backs up these files.

Yes, rsync only copies files that have been changed by default, the problem arises however that if you have millions of files with only a limited subset of them changing, rsync will still spend a lot of time checking meta-data and checksums to work out what has changed.  Using this tool allows rsync to skip this check.

So you don't repeat the mistake I made, because this is a console script, you can't simply double click the .au3 file or run "AutoIt3.exe FileName.au3" to use it.  You won't get any output.  You need to either compile the script into an executable using Aut2exe.exe with the "/console" switch or run this script from within the AutoIt3 provided SciTE-Lite editor.

Finally, my excuse for code in this script being ugly and inefficient is that this is the first time I have ever worked with AutoIt code and there are large portions of Joakim's code that I don't fully understand.  Sorry.

##Usage
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
     
More doco to come once this project matures a little more.
