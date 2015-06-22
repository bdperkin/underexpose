Name:		underexpose
Version:	0.0.3
Release:	1%{?dist}
Summary:	Anonymous, private, and caching web proxy installer.

Group:		Applications/Internet
License:	GPLv2
URL:		https://github.com/bdperkin/%{name}
Source0:	https://github.com/bdperkin/%{name}/sources/%{name}-%{version}.tar.gz

BuildArch:	noarch
BuildRequires:	asciidoc
BuildRequires:	docbook-style-xsl
BuildRequires:	/usr/bin/groff
BuildRequires:	libxslt
BuildRequires:	pandoc
BuildRequires:	/usr/bin/perltidy
BuildRequires:	/usr/bin/podchecker
BuildRequires:	w3m
Requires:	/usr/bin/perl
Requires:	/usr/bin/perldoc
Requires:	perl(Getopt::Long)
Requires:	perl(Pod::Usage)
Requires:	perl(strict)
Requires:	perl(warnings)
Requires:	policycoreutils-python
Requires:	privoxy
Requires:	squid
Requires:	tor

%define NameUpper %{expand:%%(echo %{name} | tr [:lower:] [:upper:])}
%define NameMixed %{expand:%%(echo %{name} | %{__sed} -e "s/\\([a-z]\\)\\([a-zA-Z0-9]*\\)/\\u\\1\\2/g")}
%define NameLower %{expand:%%(echo %{name} | tr [:upper:] [:lower:])}
%define Year %{expand:%%(date "+%Y")}
%define DocFiles ACKNOWLEDGEMENTS AUTHOR AUTHORS AVAILABILITY BUGS CAVEATS COPYING COPYRIGHT DESCRIPTION LICENSE NAME NOTES OPTIONS OUTPUT README.md RESOURCES SYNOPSIS
%define SubFiles %{name} %{name}.8.asciidoc %{DocFiles} man.asciidoc systemd/privoxy@.service systemd/squid@.service systemd/%{name}.target
%define DocFormats chunked htmlhelp manpage text xhtml

%description
Perl installer to setup and configure a caching web proxy that uses non-caching web proxies, with advanced filtering capabilities, and a system enabling users to communicate anonymously on the Internet.

%prep
%setup -q

%clean
%{__rm} -rf $RPM_BUILD_ROOT

%build
%{__cp} %{name}.pl %{name}
%{__sed} -i -e s/%{NAME}/%{name}/g %{SubFiles}
%{__sed} -i -e s/%{NAMEUPPER}/%{NameUpper}/g %{SubFiles}
%{__sed} -i -e s/%{NAMEMIXED}/%{NameMixed}/g %{SubFiles}
%{__sed} -i -e s/%{NAMELOWER}/%{NameLower}/g %{SubFiles}
%{__sed} -i -e s/%{VERSION}/%{version}/g %{SubFiles}
%{__sed} -i -e s/%{RELEASE}/%{release}/g %{SubFiles}
%{__sed} -i -e s/%{YEAR}/%{Year}/g %{SubFiles}
for f in %{DocFormats}; do %{__mkdir_p} $f; a2x -D $f -d manpage -f $f %{name}.8.asciidoc; done
groff -e -mandoc -Tascii manpage/%{name}.8 > manpage/%{name}.8.groff
%{__mkdir_p} pod
./groff2pod.pl manpage/%{name}.8.groff pod/%{name}.8.pod
podchecker pod/%{name}.8.pod
cat pod/%{name}.8.pod >> %{name}
perltidy -b %{name}
podchecker %{name}
pandoc -f html -t markdown -s -o README.md.pandoc xhtml/%{name}.8.html
cat README.md.pandoc | %{__grep} -v ^% | %{__sed} -e 's/\*\*/\*/g' | %{__sed} -e 's/^\ \*/\n\ \*/g' | %{__sed} -e 's/\[\*/\[\ \*/g' | %{__sed} -e 's/\*\]/\*\ \]/g' | %{__sed} -e 's/{\*/{\ \*/g' | %{__sed} -e 's/\*}/\*\ }/g' | %{__sed} -e 's/|\*/|\ \*/g' | %{__sed} -e 's/\*|/\*\ |/g' | %{__sed} -e 's/=\*/=\ \*/g' | %{__sed} -e 's/\*=/\*\ =/g' > README.md 

%install
%{__rm} -rf $RPM_BUILD_ROOT
%{__mkdir_p} %{buildroot}%{_bindir}
%{__mkdir_p} %{buildroot}%{_prefix}/lib/systemd/system
%{__mkdir_p} %{buildroot}%{_mandir}/man8
%{__mkdir_p} %{buildroot}%{_sysconfdir}/%{name}
%{__mkdir_p} %{buildroot}%{_sysconfdir}/logrotate.d
%{__mkdir_p} %{buildroot}%{_sysconfdir}/sysconfig
%{__mkdir_p} %{buildroot}%{_var}/log/%{name}
%{__install} %{name} %{buildroot}%{_bindir}
%{__install} --mode=0644 systemd/privoxy@.service %{buildroot}%{_prefix}/lib/systemd/system
%{__install} --mode=0644 systemd/squid@.service %{buildroot}%{_prefix}/lib/systemd/system
%{__install} --mode=0644 systemd/%{name}.target %{buildroot}%{_prefix}/lib/systemd/system
%{__install} --mode=0644 /dev/null %{buildroot}%{_sysconfdir}/%{name}/%{name}.conf
%{__install} --mode=0644 log4perl.conf %{buildroot}%{_sysconfdir}/%{name}
%{__install} --mode=0644 logrotate/%{name} %{buildroot}%{_sysconfdir}/logrotate.d
%{__install} --mode=0644 sysconfig/privoxy %{buildroot}%{_sysconfdir}/sysconfig
%{__install} --mode=0644 sysconfig/tor %{buildroot}%{_sysconfdir}/sysconfig
%{__gzip} -c manpage/%{name}.8 > %{buildroot}/%{_mandir}/man8/%{name}.8.gz

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_prefix}/lib/systemd/system/privoxy@.service
%{_prefix}/lib/systemd/system/squid@.service
%{_prefix}/lib/systemd/system/%{name}.target
%doc %{DocFiles}
%doc %{DocFormats} pod
%doc %{_mandir}/man8/%{name}.8.gz
%dir %{_var}/log/%{name}
%dir %{_sysconfdir}/%{name}
%config %{_sysconfdir}/%{name}/%{name}.conf
%config %{_sysconfdir}/%{name}/log4perl.conf
%config %{_sysconfdir}/logrotate.d/%{name}
%config %{_sysconfdir}/sysconfig/privoxy
%config %{_sysconfdir}/sysconfig/tor

%changelog
* Fri Dec 06 2013 Brandon Perkins <bperkins@redhat.com> 0.0.3-1
- cURL options
- Parse command line options
- Initialize GetOptions variables
- Help function
- Version function
- Initialize Logger
- Set output level
- If multiple outputs are specified, the most verbose will be used
- Setup temporary directory
- Determine if SELinux is enabled and enforcing
- SELinux port types
- Configuration file locations
- Log rotate file locations
- Data directory locations
- Log directory locations
- Checking for invalid options
- Running Setup
- Running Uninstaller
- Running Installer
- cURL browser setup
- Get SELinux port status before run
- Get SELinux fcontext status before run
- Tor Circuit installation
- Tor SELinux port type modifications
- Tor configuration file generation
- Tor systemd system and service management
- Tor simple tests
- Privoxy Circuit installation
- Privoxy SELinux port type modifications
- Privoxy configuration file generation
- Privoxy systemd system and service management
- Privoxy simple tests
- Squid installation
- Squid SELinux port type modifications
- Squid configuration file generation
- Squid systemd system and service management
- Squid simple tests
- systemd system and service management
- Get SELinux port status after run
- Get SELinux port type subtractions
- Get SELinux port type additions
- Get SELinux fcontext status after run
- Get SELinux fcontext type subtractions
- Get SELinux fcontext type additions
- Load all command-line arguments into hash
- Read all configuration file variables and values into hash
- Write all configuration variables and values into configuration file
- Check all configuration variables for validity
- Run system calls/commands
* Fri Oct 25 2013 Brandon Perkins <bperkins@redhat.com> 0.0.2-1
- Use tito CustomBuilder. (bperkins@redhat.com)
- Add groff2pod for document building. (bperkins@redhat.com)
- Get documentation framework setup. (bperkins@redhat.com)
- Perl script placeholder. (bperkins@redhat.com)
- Sane starting point for spec file. (bperkins@redhat.com)

* Fri Oct 25 2013 Brandon Perkins <bperkins@redhat.com> 0.0.1-1
- new package built with tito
