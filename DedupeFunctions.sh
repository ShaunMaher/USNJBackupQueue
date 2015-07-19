#!/bin/bash
# Because I have pulled functionallity from two different scripts created by the
# same author that do similar functions, there were several functions that
# existed in both sources which made AutoIt3 sad.  This script just detects the
# duplicates so I know which can be deleted.
while read FUNCTION; do
  if [ $(grep -c "Func ${FUNCTION}" MftRef2Name_Functions.au3) -gt 0 ]; then
    echo "${FUNCTION}"
  fi
done < <(cat UsnJrnl2Csv_Functions.au3 |grep '^Func ' | awk '{print $2}' | awk 'BEGIN{FS="("}{print $1}')
