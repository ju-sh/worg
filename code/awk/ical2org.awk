# awk script for converting an iCal formatted file to a sequence of org-mode headings.
# this may not work in general but seems to work for day and timed events from Google's
# calendar, which is really all I need right now...
#
# usage:
#   awk -f THISFILE < icalinputfile.ics > orgmodeentries.org
#
# Note: change org meta information generated below for author and
# email entries!
#
# Known bugs:
# - not so much a bug as a possible assumption: date entries with no time
#   specified are assumed to be independent of the time zone.
#
# Eric S Fraga
# 20100629 - initial version
# 20100708 - added end times to timed events
#          - adjust times according to time zone information
#          - fixed incorrect transfer for entries with ":" embedded within the text
#          - added support for multi-line summary entries (which become headlines)
# 20100709 - incorporated time zone identification
#          - fixed processing of continuation lines as Google seems to
#            have changed, in the last day, the number of spaces at
#            the start of the line for each continuation...
#          - remove backslashes used to protect commas in iCal text entries
# no further revision log after this as the file was moved into a git
# repository...
#
# Last change: 2011.01.28 16:08:03
#----------------------------------------------------------------------------------

# a function to take the iCal formatted date+time, convert it into an
# internal form (seconds since time 0), and adjust according to the
# local time zone (specified by +-seconds calculated in the BEGIN
# section)

function datetimestamp(input)
{
    # convert the iCal Date+Time entry to a format that mktime can understand
    datespec = gensub("([0-9][0-9][0-9][0-9])([0-9][0-9])([0-9][0-9])T([0-9][0-9])([0-9][0-9])([0-9][0-9]).*[\r]*", "\\1 \\2 \\3 \\4 \\5 \\6", "g", input);
    # print "date spec : " datespec; convert this date+time into
    # seconds from the beginning of time and include adjustment for
    # time zone, as determined in the BEGIN section below.  For time
    # zone adjustment, I have not tested edge effects, specifically
    # what happens when UTC time is a different day to local time and
    # especially when an event with a duration crosses midnight in UTC
    # time.  It should work but...
    timestamp = mktime(datespec) + seconds;
    # print "adjusted    : " timestamp
    # print "Time stamp  : " strftime("%Y-%m-%d %H:%M", timestamp);
    return timestamp;
}

BEGIN {
    # use a colon to separate the type of data line from the actual contents
    FS = ":";
    
    # determine the number of seconds to use for adjusting for time
    # zone difference from UTC.  This is used in the function
    # datetimestamp above.  The time zone information returned by
    # strftime() is in hours * 100 so we multiply by 36 to get
    # seconds.  This does not work for time zones that are not an
    # integral multiple of hours (e.g. Newfoundland)
    seconds = gensub("([+-])0", "\\1", "", strftime("%z")) * 36;
    
    date = "";
    entry = ""
    first = 1;			# true until an event has been found
    headline = ""
    icalentry = ""  # the full entry for inspection
    id = ""
    indescription = 0;
    time2given = 0;
    
    print "#+TITLE:     Main Google calendar entries"
    print "#+AUTHOR:    Eric S Fraga"
    print "#+EMAIL:     e.fraga@ucl.ac.uk"
    print "#+DESCRIPTION: converted using the ical2org awk script"
    print "#+CATEGORY: " NAME
    print " "
}

# continuation lines (at least from Google) start with two spaces
# if the continuation is after a description or a summary, append the entry
# to the respective variable

/^[ ]+/ { 
    if (indescription) {
	entry = entry gensub("\r", "", "g", gensub("^[ ]+", "", "", $0));
    } else if (insummary) {
	summary = summary gensub("\r", "", "g", gensub("^[ ]+", "", "", $0))
    }
    icalentry = icalentry "\n" $0
}

/^BEGIN:VEVENT/ {
    # start of an event.  if this is the first, output the preamble from the iCal file
    if (first) {
	print "* COMMENT original iCal preamble"
	print gensub("\r", "", "g", icalentry)
	icalentry = ""
    }
    first = false;
}
# any line that starts at the left with a non-space character is a new data field

/^[A-Z]/ {
    # we ignore DTSTAMP lines as they change every time you download
    # the iCal format file which leads to a change in the converted
    # org file as I output the original input.  This change, which is
    # really content free, makes a revision control system update the
    # repository and confuses.
    if (! index("DTSTAMP", $1)) icalentry = icalentry "\n" $0
    # this line terminates the collection of description and summary entries
    indescription = 0;
    insummary = 0;
}

# this type of entry represents a day entry, not timed, with date stamp YYYYMMDD

/^DTSTART;[^:]*/ {
    date = gensub("([0-9][0-9][0-9][0-9])([0-9][0-9])([0-9][0-9]).*[\r]", "\\1-\\2-\\3", "g", $2)
    # print date
}

# this represents a timed entry with date and time stamp YYYYMMDDTHHMMSS
# we ignore the seconds

/^DTSTART:/ {
    # print $0
    date = strftime("%Y-%m-%d %a %H:%M", datetimestamp($2));
    # print date;
}

# and the same for the end date; here we extract only the time and append this to the 
# date+time found by the DTSTART entry.  We assume that entry was there, of course.
# should probably add some error checking here!  In time...

/^DTEND:/ {
    # print $0
    time2 = strftime("%H:%M", datetimestamp($2));
    date = date "-" time2;
}

# The description will the contents of the entry in org-mode.
# this line may be continued.

/^DESCRIPTION/ { 
    $1 = "";
    entry = entry "\n" gensub("\r", "", "g", $0);
    indescription = 1;
}

# the summary will be the org heading

/^SUMMARY/ { 
    $1 = "";
    summary = gensub("\r", "", "g", $0);
    insummary = 1;
}

# the unique ID will be stored as a property of the entry

/^UID/ { 
    $1 = "";
    id = gensub("\r", "", "g", $0);
}

# when we reach the end of the event line, we output everything we
# have collected so far, creating a top level org headline with the
# date/time stamp, unique ID property and the contents, if any

/^END:VEVENT/ {
    # translate \n sequences to actual newlines and unprotect commas (,)
    print "* " gensub("\\\\,", ",", "g", gensub("\\\\n", " ", "g", summary))
    print "  :PROPERTIES:"
    print "  :ID:       " id
    print "  :END:"
    print "  <" date ">"
    # for the entry, convert all embedded "\n" strings to actual newlines
    print ""
    # translate \n sequences to actual newlines and unprotect commas (,)
    print gensub("\\\\,", ",", "g", gensub("\\\\n", "\n", "g", entry));
    print "** COMMENT original iCal entry"
    print gensub("\r", "", "g", icalentry)
    summary = ""
    date = ""
    entry = ""
    icalentry = ""
    indescription = 0
    insummary = 0
}

# Local Variables:
# time-stamp-line-limit: 1000
# time-stamp-format: "%04y.%02m.%02d %02H:%02M:%02S"
# time-stamp-active: t
# time-stamp-start: "Last change:[ \t]+"
# time-stamp-end: "$"
# End: