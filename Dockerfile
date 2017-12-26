FROM zasdfgbnm/archlinux-yaourt
RUN yaourt -Syua --noconfirm git qemu
USER root
# FROM debian:sid
# RUN apt-get update && apt-get -y upgrade && apt-get -y install git build-essential qemu qemu-kvm
COPY . /lkp-tests/
RUN cd lkp-tests && make install
RUN yes | lkp install --global-gem
#RUN cd /lkp-tests/jobs && lkp install --global-gem $(ls)
