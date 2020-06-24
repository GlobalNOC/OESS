---
layout: operations-manual
title: Installation
name: installation
---

## Install via Package Manager

### 1. Configure Package Management System

Create `/etc/yum.repos.d/globalnoc-public-el7.repo` using the content
below. Then run `sudo yum makecache` to update your local cache of
available software packages.

```
[globalnoc-public-el7]
name=GlobalNOC Public el7 Packages - $basearch
baseurl=https://repo-public.grnoc.iu.edu/repo/7/$basearch
enabled=1
gpgcheck=1
gpgkey=https://repo-public.grnoc.iu.edu/repo/RPM-GPG-KEY-GRNOC7
```

### 2. Install the OESS Packages

```
sudo yum install -y perl-OESS oess-core oess-frontend
```

### 3. Run the Setup Script

```
sudo perl /usr/bin/oess_setup.pl
```

### 4. Start OESS

You can start OESS by running the following command:

```
sudo systemctl start oess
```

To verify the service is running use:

```
sudo systemctl status oess
```
