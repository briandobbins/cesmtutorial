#!/bin/bash

# Check if we're running the headnode software installation:
if [ "HEAD" == "$1" ]; then

# Install the yum repo for all the oneAPI packages:
cat << EOF > /etc/yum.repos.d/oneAPI.repo
[oneAPI]
name=Intel(R) oneAPI repository
baseurl=https://yum.repos.intel.com/oneapi
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB
EOF

# Install various tools we need for users (some of these are probably already on here, but I'm aiming for 
# consistency with the container setup, so duplicates will just be skipped)
yum -y install vim emacs-nox git subversion which sudo csh make m4 cmake wget file byacc curl-devel zlib-devel
yum -y install perl-XML-LibXML gcc-gfortran gcc-c++ dnf-plugins-core python3 perl-core ftp numactl-devel words expect

# Install the 'limited' set of Intel tools we need - note that this also downloads
# and installs >25 other packages, but it's still only a 3GB install, vs the 20GB
# you get from the 'intel-hpckit' meta-package.
yum -y install intel-oneapi-compiler-fortran-2021.4.0 intel-oneapi-compiler-dpcpp-cpp-and-cpp-classic-2021.4.0 intel-oneapi-mpi-devel-2021.4.0 
# Update:
yum -y update

# OK, check if our precompiled stuff is available; if not, we'll build it:
curl ftp://cesm-inputdata-lowres1.cgd.ucar.edu/cesm/low-res/cloud/ncar_software_full.tar.gz --output /tmp/ncar_software.tar.gz
if [ -f /tmp/ncar_software.tar.gz ]; then
  cd /opt/ncar/ && tar zxvf /tmp/ncar_software.tar.gz
  rm -f /tmp/ncar_software.tar.gz
else
  export LIBRARY_PATH=/opt/ncar/software/lib
  export LD_LIBRARY_PATH=/opt/ncar/software/lib
  export CPATH=/opt/ncar/software/include
  export FPATH=/opt/ncar/software/include
  source /opt/intel/oneapi/setvars.sh
  mkdir /tmp/sources
  cd /tmp/sources
  wget -q https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.12/hdf5-1.12.0/src/hdf5-1.12.0.tar.gz
  tar zxf hdf5-1.12.0.tar.gz
  cd hdf5-1.12.0
  ./configure --prefix=/opt/ncar/software CC=icc CXX=icpc FC=ifort
  make -j 2 install
  cd /tmp/sources
  wget -q ftp://ftp.unidata.ucar.edu/pub/netcdf/netcdf-c-4.7.4.tar.gz
  tar zxf netcdf-c-4.7.4.tar.gz
  cd netcdf-c-4.7.4
  ./configure --prefix=/opt/ncar/software CC=icc CXX=icpc FC=ifort
  make -j 2 install
  ldconfig
  cd /tmp/sources
  wget -q ftp://ftp.unidata.ucar.edu/pub/netcdf/netcdf-fortran-4.5.3.tar.gz
  tar zxf netcdf-fortran-4.5.3.tar.gz
  cd netcdf-fortran-4.5.3
  ./configure --prefix=/opt/ncar/software CC=icc CXX=icpc FC=ifort
  make -j 2 install
  ldconfig
  cd /tmp/sources
  wget -q https://parallel-netcdf.github.io/Release/pnetcdf-1.12.1.tar.gz
  tar zxf pnetcdf-1.12.1.tar.gz
  cd pnetcdf-1.12.1
  ./configure --prefix=/opt/ncar/software CC=mpicc CXX=mpicxx FC=mpiifort
  make -j 2 install
  ldconfig
  rm -rf /tmp/sources
fi

# Get the CESM version we're using too, first by ensuring we have the SVN authentication handled:
svn --username=guestuser --password=friendly list https://svn-ccsm-models.cgd.ucar.edu << EOF
p
yes
EOF

cd /opt/ncar
git clone -b cesm2.1.4-rc.08-aws https://github.com/briandobbins/CESM.git cesm
cd cesm
./manage_externals/checkout_externals

# Change SSH to enable passwords:
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd.service

# Set the hostname:
hostname cesm-workshop


# add /scratch/inputdata
mkdir -p /scratch/inputdata
chown -R root:users /scratch/inputdata
chmod -R g+rw /scratch/inputdata

# Add 'switchuser' alias:
cat << EOF > /usr/local/sbin/switchuser
#!/bin/bash
if [ "\$#" -ne 1 ]; then
  echo "Usage: switchuser <user name>"
  exit
fi
sudo -u \$1 -i
EOF
chmod +x /usr/local/sbin/switchuser


fi # End of HEAD being specified in the command-line

# Fix user limits:
cat << EOF >> /etc/security/limits.conf
@user	soft	stack		-1
@user	hard	stack		-1
@admin  soft	stack		-1
@admin	hard	stack		-1
EOF

# Also add the compilers to the /etc/profile.d/oneapi.sh
echo 'source /opt/intel/oneapi/setvars.sh --force > /dev/null' > /etc/profile.d/oneapi.sh

# And create the /etc/profile/cesm.sh setup:
cat << EOF > /etc/profile.d/cesm.sh
export CIME_MACHINE=aws
export CESMROOT=/opt/ncar/cesm
export PATH=${PATH}:/opt/ncar/cesm/cime/scripts
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/opt/ncar/software/lib

export I_MPI_PMI_LIBRARY=/opt/slurm/lib/libpmi.so
export I_MPI_OFI_LIBRARY_INTERNAL=0
export I_MPI_FABRICS=ofi
export I_MPI_OFI_PROVIDER=efa
export TMOUT=0

EOF


# Set up the 'python' alias to point to Python3 -- this is going away for newer CESM releases, I think, but may
# be needed for this 2.1.4-rcX version
ln -s /usr/bin/python3 /usr/bin/python

# Now add all our libraries, into /opt/ncar/software/lib so they're accessible by compute nodes:
# (Note: This needs to be cleaned up for better updating of versions later!)
# We do this in /opt so that compute nodes don't need to have all this stuff installed, making
# boot time much faster.  The first line adds our location to the standard LD search path.
echo '/opt/ncar/software/lib' > /etc/ld.so.conf.d/ncar.conf


# Add users:
groupadd admin
cd /root
wget https://raw.githubusercontent.com/briandobbins/cesmtutorial/main/scripts/accounts.py
chmod +x accounts.py
aws s3 cp s3://agu2021-cesm-tutorial/WorkshopList.csv .
python3 accounts.py ./WorkshopList.csv


# Extra stuff at the end:
if [ "HEAD" == "$1" ]; then

# Create passwordless SSH creation script:
cat << EOF > /usr/local/sbin/setup_passwordless_ssh
#!/bin/bash
mkdir ~/.ssh; ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -q -N "" ; cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys ; chmod 0600 ~/.ssh/authorized_keys
EOF
chmod +x /usr/local/sbin/setup_passwordless_ssh

# Create SSH keys on the head node for all users added
while read -r line; do
  username=$(echo $line | awk -F':' '{print $1}')
  runuser -l ${username} -c /usr/local/sbin/setup_passwordless_ssh
done < /root/users.log

# Append build template to ~/.bashrc for each user
while read -r line; do
  username=$(echo $line | awk -F':' '{print $1}')
  runuser -l ${username} -c 'echo "export CESM_BLD_TEMPLATE=/scratch/inputdata/build_template/B1850-tutorial/bld" >> ~/.bashrc'
done < /root/users.log


# Fix permissions on /scratch
chmod 755 /scratch/

fi

