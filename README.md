
Name
----

underexpose — Anonymous, private, and caching web proxy installer.

Synopsis
--------

*underexpose* [ *-q* | *--quiet* ] [ *-v* | *--verbose* ]
[ *-d* | *--debug* ]

*underexpose* { *--version* | *-V* }

*underexpose* { *--help* | *-h* }

*underexpose* { *--man* | *-m* }

DESCRIPTION
-----------

The underexpose(8) command is a Perl installer to setup and configure a
caching web proxy that uses non-caching web proxies, with advanced
filtering capabilities, and a system enabling users to communicate
anonymously on the Internet.

OPTIONS
-------

Command line options are used to specify various startup options for
underexpose:


 *-d*, *--debug* 
:   Debug output.

 *-h*, *--help* 
:   Print or show help information and exit.

 *-m*, *--man* 
:   Print the entire manual page and exit.

 *-q*, *--quiet* 
:   Quiet output.

 *-v*, *--verbose* 
:   Verbose output.

 *-V*, *--version* 
:   Print or show the program version and release number and exit.

EXIT STATUS
-----------

The underexpose return code to the parent process (or caller) when it
has finished executing may be one of:


 *0* 
:   Success.

 *1* 
:   Failure (syntax or usage error; configuration error; unexpected
    error).

BUGS
----

Report any issues at:
[https://github.com/bdperkin/underexpose/issues](https://github.com/bdperkin/underexpose/issues)

AUTHORS
-------

Brandon Perkins \<[bperkins@redhat.com](mailto:bperkins@redhat.com)\>

RESOURCES
---------

GitHub:
[https://github.com/bdperkin/underexpose](https://github.com/bdperkin/underexpose)

COPYING
-------

Copyright (C) 2013-2013 Brandon Perkins
\<[bperkins@redhat.com](mailto:bperkins@redhat.com)\>

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at your
option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
