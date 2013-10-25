Name:		underexpose
Version:	0.0.0
Release:	1%{?dist}
Summary:	Anonymous, private, and caching web proxy installer.

Group:		Applications/Internet
License:	GPLv2
URL:		https://github.com/bdperkin/%{name}
Source0:	https://github.com/bdperkin/%{name}/sources/%{name}-%{version}.tar.gz

BuildRequires:  asciidoc
BuildRequires:  docbook-style-xsl
BuildRequires:  /usr/bin/groff
BuildRequires:  libxslt
BuildRequires:  pandoc
BuildRequires:  /usr/bin/perltidy
BuildRequires:  /usr/bin/podchecker
BuildRequires:  w3m
Requires:       /usr/bin/perl
Requires:       /usr/bin/perldoc
Requires:       perl(Getopt::Long)
Requires:       perl(Pod::Usage)
Requires:       perl(strict)
Requires:       perl(warnings)

%description


%prep
%setup -q


%build
%configure
make %{?_smp_mflags}


%install
make install DESTDIR=%{buildroot}


%files
%doc



%changelog

