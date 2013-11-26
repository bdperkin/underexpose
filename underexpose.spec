Name:		underexpose
Version:	0.0.2
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
%define SubFiles %{name} %{name}.8.asciidoc %{DocFiles} man.asciidoc
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
%{__mkdir_p} %{buildroot}%{_sysconfdir}/sysconfig
%{__mkdir_p} %{buildroot}%{_var}/log/%{name}
%{__install} %{name} %{buildroot}%{_bindir}
%{__install} systemd/privoxy@.service %{buildroot}%{_prefix}/lib/systemd/system
%{__install} systemd/squid@.service %{buildroot}%{_prefix}/lib/systemd/system
%{__install} systemd/tor@.service %{buildroot}%{_prefix}/lib/systemd/system
%{__install} /dev/null %{buildroot}%{_sysconfdir}/%{name}/%{name}.conf
%{__install} log4perl.conf %{buildroot}%{_sysconfdir}/%{name}
%{__install} sysconfig/privoxy %{buildroot}%{_sysconfdir}/sysconfig
%{__install} sysconfig/tor %{buildroot}%{_sysconfdir}/sysconfig
%{__gzip} -c manpage/%{name}.8 > %{buildroot}/%{_mandir}/man8/%{name}.8.gz

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_prefix}/lib/systemd/system/privoxy@.service
%{_prefix}/lib/systemd/system/squid@.service
%{_prefix}/lib/systemd/system/tor@.service
%doc %{DocFiles}
%doc %{DocFormats} pod
%doc %{_mandir}/man8/%{name}.8.gz
%dir %{_var}/log/%{name}
%dir %{_sysconfdir}/%{name}
%config %{_sysconfdir}/%{name}/%{name}.conf
%config %{_sysconfdir}/%{name}/log4perl.conf
%config %{_sysconfdir}/sysconfig/privoxy
%config %{_sysconfdir}/sysconfig/tor

%changelog
* Fri Oct 25 2013 Brandon Perkins <bperkins@redhat.com> 0.0.2-1
- Use tito CustomBuilder. (bperkins@redhat.com)
- Add groff2pod for document building. (bperkins@redhat.com)
- Get documentation framework setup. (bperkins@redhat.com)
- Perl script placeholder. (bperkins@redhat.com)
- Sane starting point for spec file. (bperkins@redhat.com)

* Fri Oct 25 2013 Brandon Perkins <bperkins@redhat.com> 0.0.1-1
- new package built with tito
