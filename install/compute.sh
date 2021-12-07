#!/bin/bash


# Install various tools we need for users (some of these are probably already on here, but I'm aiming for 
# consistency with the container setup, so duplicates will just be skipped)
#yum -y install vim emacs-nox git subversion which sudo csh make m4 cmake wget file byacc curl-devel zlib-devel
#yum -y install perl-XML-LibXML gcc-gfortran gcc-c++ dnf-plugins-core python3 perl-core ftp numactl-devel

# Set up the 'python' alias to point to Python3 -- this is going away for newer CESM releases, I think, but may
# be needed for this 2.1.4-rcX version
ln -s /usr/bin/python3 /usr/bin/python

# Now add all our libraries, into /opt/ncar/software/lib so they're accessible by compute nodes:
# (Note: This needs to be cleaned up for better updating of versions later!)
# We do this in /opt so that compute nodes don't need to have all this stuff installed, making
# boot time much faster.  The first line adds our location to the standard LD search path.
echo '/opt/ncar/software/lib' > /etc/ld.so.conf.d/ncar.conf

# Also add the compilers to the /etc/profile.d/oneapi.sh
echo 'source /opt/intel/oneapi/setvars.sh > /dev/null' > /etc/profile.d/oneapi.sh

