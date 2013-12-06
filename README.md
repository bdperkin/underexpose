
Name
----

underexpose — Anonymous, private, and caching web proxy installer.

Synopsis
--------

*underexpose* { *--setup* | *-S* } [ *-q* | *--quiet* ]
[ *-v* | *--verbose* ] [ *-d* | *--debug* ] [ *-c*
*circuits* | *--circuits* = *circuits* ]

*underexpose* [ *-q* | *--quiet* ] [ *-v* | *--verbose* ]
[ *-d* | *--debug* ]

*underexpose* { *--uninstall* | *-U* } [ *-q* | *--quiet* ]
[ *-v* | *--verbose* ] [ *-d* | *--debug* ] [ *-c*
*circuits* | *--circuits* = *circuits* ]

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


 *-c* *circuits*, *--circuits* = *circuits* 
:   Number of circuits (Tor-Privoxy pairs) that should be installed.

 *-C* *configdir*, *--configdir* = *configdir* 
:   Configuration directory.

 *-d*, *--debug* 
:   Debug output.

 *-D* *docdir*, *--docdir* = *docdir* 
:   Documentation directory.

 *-h*, *--help* 
:   Print or show help information and exit.

 *-L* *logdir*, *--logdir* = *logdir* 
:   Log directory.

 *-m*, *--man* 
:   Print the entire manual page and exit.

 *-M* *mandir*, *--mandir* = *mandir* 
:   Reference manuals directory.

 *-q*, *--quiet* 
:   Quiet output.

 *-S*, *--setup* 
:   Run setup only (no installation).

 *-U*, *--uninstall* 
:   Run uninstallation.

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

~~~~ {.literallayout}
GitHub: <https://github.com/bdperkin/underexpose>
~~~~

~~~~ {.literallayout}
Tor, Second-generation onion router: <https://www.torproject.org/>
~~~~

~~~~ {.literallayout}
Tor test site: <https://check.torproject.org/>
~~~~

~~~~ {.literallayout}
Privoxy Home page: <http://www.privoxy.org/>
~~~~

~~~~ {.literallayout}
Privoxy FAQ: <http://www.privoxy.org/faq/>
~~~~

~~~~ {.literallayout}
Privoxy developer manual: <http://www.privoxy.org/developer-manual/>
~~~~

~~~~ {.literallayout}
Privoxy Project Page: <https://sourceforge.net/projects/ijbswa/>
~~~~

~~~~ {.literallayout}
Privoxy web-based user interface: <http://config.privoxy.org/>
~~~~

~~~~ {.literallayout}
Privoxy web-based user interface shortcut: <http://p.p/>
~~~~

~~~~ {.literallayout}
Squid wiki and examples: <http://wiki.squid-cache.org/>
~~~~

~~~~ {.literallayout}
Squid FAQ wiki: <http://wiki.squid-cache.org/SquidFaq>
~~~~

~~~~ {.literallayout}
Squid Configuration Manual: <http://www.squid-cache.org/Doc/config/>
~~~~

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
