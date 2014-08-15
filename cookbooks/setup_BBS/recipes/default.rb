require 'yaml'

yamlconfig = YAML.load_file "/vagrant/config.yml"

rmajor = yamlconfig["r_version"].sub(/^R-/, "").split("").first


execute "change time zone" do
    user "root"
    command "echo 'America/Los_Angeles' > /etc/timezone && dpkg-reconfigure --frontend noninteractive tzdata"
    only_if "egrep -q 'UTC|GMT' /etc/timezone"
end

user "biocbuild" do
    supports :manage_home => true
    home "/home/biocbuild"
    shell "/bin/bash"
    action :create
end

bbsdir = "/home/biocbuild/bbs-#{yamlconfig['bioc_version']}-bioc"

directory bbsdir do
    owner "biocbuild"
    group "biocbuild"
    mode "0755"
    action :create
end

directory "/home/biocbuild/.BBS" do
    owner "biocbuild"
    group "biocbuild"
    mode "0755"
    action :create
end

%w(log NodeInfo svninfo meat R).each do |dir|
    directory "#{bbsdir}/#{dir}" do
        owner "biocbuild"
        group "biocbuild"
        mode "0755"
        action :create
    end
end

%W(src public_html public_html/BBS public_html/BBS/#{yamlconfig['bioc_version']} public_html/BBS/#{yamlconfig['bioc_version']}/bioc).each do |dir|
    directory "/home/biocbuild/#{dir}" do
        owner "biocbuild"
        group "biocbuild"
        mode "0755"
        action :create
    end

end

link "/var/www/html/BBS" do
    to "/home/biocbuild/BBS"
end


base_url = "https://hedgehog.fhcrc.org/bioconductor"
if yamlconfig['use_devel']
    branch = 'trunk'
else
    branch = "branches/RELEASE_#{yamlconfig['bioc_version'].sub(".", "_")}"
end

svn_meat_url = "#{base_url}/#{branch}/madman/Rpacks"

package "subversion" do
    action :install
end

directory "/root/.subversion/servers" do
    action :create
    recursive true
    owner "root"
    group "root"
    mode "0777"
end

execute "setup svn auth" do
    cwd "/home/biocbuild"
    user "biocbuild"
    command "tar zxf /vagrant/svnauth.tar.gz"
end

execute "setup svn auth2" do
    cwd "/root"
    user "root"
    command "tar zxf /vagrant/svnauth.tar.gz"
end


# execute "atest" do
#     user "biocbuild"
#     environment({"SVN_PASS" => yamlconfig['svn_password']})
#     #command "svn co --non-interactive --no-auth-cache --username biocbuild --password $SVN_PASS #{svn_meat_url} MEAT0"
#     cwd "#{bbsdir}"
#     command "whoami > whoami.txt"
# ####uncomment_this    not_if {File.exists? "#{bbsdir}/MEAT0"}
#     # rely on STAGE1 to 'svn up' MEAT0
# end

# subversion "check out meat" do
#     repository svn_meat_url
#     #revision "HEAD__"
#     destination "#{bbsdir}/MEAT0"
#     action :checkout
#     user "biocbuild"
#     svn_username "biocbuild"
#     svn_password yamlconfig['svn_password']
# end


execute "this is a bad idea" do
    # ... but it makes svn happy below. don't know
    # why biocbuild needs to see root's svn credentials
    user "root"
    command "chmod -R a+rx /root"
end

execute "checkout meat" do
    user "biocbuild"
    environment({"SVN_PASS" => yamlconfig['svn_password']})
    command "svn checkout --non-interactive --username biocbuild --password $SVN_PASS #{svn_meat_url} MEAT0"
    cwd "#{bbsdir}"
    not_if {File.exists? "#{bbsdir}/MEAT0"}
    timeout 21600
    # rely on STAGE1 to 'svn up' MEAT0
end

%w(    libnetcdf-dev libhdf5-serial-dev sqlite libfftw3-dev libfftw3-doc
    libopenbabel-dev fftw3 fftw3-dev pkg-config xfonts-100dpi xfonts-75dpi
    libopenmpi-dev openmpi-bin mpi-default-bin openmpi-common
    libexempi3 openmpi-checkpoint python-mpi4py texlive-science
    texlive-bibtex-extra texlive-fonts-extra fortran77-compiler gfortran
    libreadline-dev libx11-dev libxt-dev texinfo apache2
).each do |pkg|
    package pkg do
        # this might timeout, but adding a 'timeout' here 
        # causes an error. hmmm.
        # texlive-science seems to be the culprit
        # also texlive-fonts-extra
        action :install
    end
end


package "git" do
    action :install
end

remote_file "copy ssh key" do
    path "/home/biocbuild/.ssh/id_rsa"
    source "file:///vagrant/id_rsa"
    owner "biocbuild"
    group "biocbuild"
    mode 0400
    not_if {File.exists? "/home/biocbuild/.ssh/id_rsa"}
end

execute "check out forked BBS" do
    user "biocbuild"
    cwd "/home/biocbuild"
    action :run
    environment({"GIT_TRACE" => "1", "GIT_SSH" => "/vagrant/ssh"})
    command "git clone git@zin1:/home/git/BBS-fork.git BBS"
    #command "git clone git@zin1:/home/git/BBS-fork.git BBS"
    not_if {File.exists? "/home/biocbuild/BBS"}
end

execute "update forked BBS" do
    user "biocbuild"
    cwd "/home/biocbuild/BBS"
    action :run
    environment ({"GIT_TRACE"=>"1", "GIT_SSH"=>"/vagrant/ssh"})
    command "git pull"
    only_if {File.exists? "/home/biocbuild/BBS"}
end



# check out (forked) BBS
# from git@zin1:/home/git/BBS-fork.git
# set machine name in config.yml, make sure BBS knows about it 
# and sees it as the main builder

# download and install R...
# http://cran.r-project.org/src/base/R-3/R-3.1.1.tar.gz

r_url = "http://cran.r-project.org/src/base/R-#{rmajor}/#{yamlconfig['r_version']}.tar.gz"
srcfile = "/home/biocbuild/src/#{yamlconfig['r_version']}.tar.gz"

remote_file srcfile do
    source r_url
end

execute "untar R" do
    action :run
    user "biocbuild"
    cwd "/home/biocbuild/src"
    command "tar zxf #{srcfile}"
    not_if {File.exists? "/home/biocbuild/src/#{yamlconfig['r_version']}"}
end

execute "build R" do
    action :run
    user "biocbuild"
    cwd "#{bbsdir}/R"
    command "/home/biocbuild/src/#{yamlconfig['r_version']}/configure --enable-R-shlib && make"
    not_if {File.exists? "#{bbsdir}/R/bin/R"}
end

# download biocinstaller? set devel?

execute "set R flags" do
    action :run
    user "biocbuild"
    cwd "#{bbsdir}/R/etc"
    # for some reason this script exits
    command "/home/biocbuild/BBS/utils/R-fix-flags.sh"
    not_if {File.exists? "#{bbsdir}/R/etc/Makeconf.original"}
end

# install apache and set it up...

# install stuff that needs to be built 'manually'

# test build by putting the following in crontab
# (setting the time to be coming up soon)

## bbs-3.0-bioc
# 20 16 * * * cd /home/biocbuild/BBS/3.0/bioc/bbsvm && ./prerun.sh >>/home/biocbuild/bbs-3.0-bioc/log/bbsvm.log 2>&1
# 00 17 * * * /bin/bash --login -c 'cd /home/biocbuild/BBS/3.0/bioc/bbsvm && ./run.sh >>/home/biocbuild/bbs-3.0-bioc/log/bbsvm.log 2>&1'
## IMPORTANT: Make sure this is started AFTER 'biocbuild' has finished its "run.sh" job on ALL other nodes!
# 45 08 * * * cd /home/biocbuild/BBS/3.0/bioc/bbsvm && ./postrun.sh >>/home/biocbuild/bbs-3.0-bioc/log/bbsvm.log 2>&1


# add USER=biocbuild to crontab
# copy key to ~/.BBS and make sure corresponding public key is
# in the right place