FROM rknop/devuan-daedalus-rknop AS base
LABEL maintainer="Rob Knop <raknop@lbl.gov>"

ARG UID=95089
ARG GID=103883

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y less python3 python3-venv apache2 libapache2-mod-wsgi-py3 libapache2-mod-php \
       libcap2-bin net-tools netcat-openbsd lynx patch tmux \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/apt/lists/*

# Principle of least surprise
RUN ln -s /usr/bin/python3 /usr/bin/python

# ======================================================================
# apt-getting pip installs a full dev environment, which we don't
#   want in our final image.  (400 unnecessary MB.)

FROM base AS build

RUN apt-get update && apt-get install -y python3-pip

RUN mkdir /venv
RUN python3 -mvenv /venv

RUN source /venv/bin/activate \
  && pip install web.py

# ======================================================================

FROM base AS final

COPY --from=build /venv/ /venv/
ENV PATH=/venv/bin:$PATH

RUN /sbin/setcap 'cap_net_bind_service=+ep' /usr/sbin/apache2

RUN ln -s ../mods-available/socache_shmcb.load /etc/apache2/mods-enabled/socache_shmcb.load
RUN ln -s ../mods-available/ssl.load /etc/apache2/mods-enabled/ssl.load
RUN ln -s ../mods-available/ssl.conf /etc/apache2/mods-enabled/ssl.conf
RUN ln -s ../mods-available/rewrite.load /etc/apache2/mods-enabled/rewrite.load
RUN rm /etc/apache2/sites-enabled/000-default.conf
RUN echo "Listen 8080" > /etc/apache2/ports.conf
COPY monitorserver.conf /etc/apache2/sites-available/
RUN ln -s ../sites-available/monitorserver.conf /etc/apache2/sites-enabled/monitorserver.conf

# Patches
RUN mkdir patches
COPY ./patches/* patches/
RUN patch -p1 /etc/apache2/mods-available/mpm_event.conf < ./patches/mpm_event.conf_patch
RUN rm -rf patches

# Do scary permissions stuff since we'll have to run
#  as a normal user.  But, given that we're running as
#  a normal user, that makes this less scary.
RUN mkdir -p /var/run/apache2
RUN chmod a+rwx /var/run/apache2
RUN mkdir -p /var/lock/apache2
RUN chmod a+rwx /var/lock/apache2
RUN chmod -R a+rx /etc/ssl/private
RUN mkdir -p /var/log/apache2
RUN chmod -R a+rwx /var/log/apache2

# /secrets, /dest, and /var/www/html need to get replaced with bind mounts at runtime
RUN mkdir /secrets
RUN mkdir /dest
RUN mkdir /var/www/html
RUN mkdir /var/www/xfer
COPY nersc-upload-connector/connector.py /var/www/xfer/connector.py
RUN chown $UID:$GID /secrets
RUN chown $UID:$GID /dest
RUN chown -R $UID:$GID /var/www/html
RUN chown -R $UID:$GID /var/www/xfer

USER $UID:$GID
RUN apachectl start

CMD [ "apachectl", "-D", "FOREGROUND", "-D", "APACHE_CONFDIR=/etc/apache2" ]
#CMD "/bin/bash"

