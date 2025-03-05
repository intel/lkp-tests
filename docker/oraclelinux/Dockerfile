# base image can be oraclelinux:9 and etc
ARG base_image
FROM ${base_image}

# lkp install generates hosts/$HOSTNAME during create_host_config. 
# Here it requires the user to pass hostname arg to specify a consistent name instead of the container hostname when building the image.
ARG hostname=lkp-docker
ENV HOSTNAME=${hostname}

WORKDIR /lkp/lkp-tests

COPY . ./

RUN yum upgrade -y && \
    yum config-manager --set-enabled ol9_codeready_builder && \
    yum makecache && \
    yum install -y \
    # kernel-tools installs turbostat
    kernel-tools \
    make \
    # procps installs vmstat, sysctl, etc to partially persistent commonly used dependencies
    procps \
    stress-ng \
    hostname && \
    make install && \
    lkp install

ENTRYPOINT ["bash", "-c", "sleep infinity"]
