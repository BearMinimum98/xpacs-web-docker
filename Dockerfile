FROM openjdk:8u232-jdk-stretch

RUN echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90circleci \
  && echo 'DPkg::Options "--force-confnew";' >> /etc/apt/apt.conf.d/90circleci

ENV DEBIAN_FRONTEND=noninteractive

RUN if grep -q Debian /etc/os-release && grep -q jessie /etc/os-release; then \
	rm /etc/apt/sources.list \
    && echo "deb http://archive.debian.org/debian/ jessie main" >> /etc/apt/sources.list \
    && echo "deb http://security.debian.org/debian-security jessie/updates main" >> /etc/apt/sources.list \
	; fi

RUN echo 'PATH="$HOME/.local/bin:$PATH"' >> /etc/profile.d/user-local-path.sh

RUN apt-get update \
  && mkdir -p /usr/share/man/man1 \
  && apt-get install -y \
    git mercurial xvfb apt \
    locales sudo openssh-client ca-certificates tar gzip parallel \
    net-tools netcat unzip zip bzip2 gnupg curl wget make

RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

RUN locale-gen C.UTF-8 || true
ENV LANG=C.UTF-8

RUN JQ_URL="https://circle-downloads.s3.amazonaws.com/circleci-images/cache/linux-amd64/jq-latest" \
  && curl --silent --show-error --location --fail --retry 3 --output /usr/bin/jq $JQ_URL \
  && chmod +x /usr/bin/jq \
  && jq --version

RUN set -ex \
  && export DOCKER_VERSION=$(curl --silent --fail --retry 3 https://download.docker.com/linux/static/stable/x86_64/ | grep -o -e 'docker-[.0-9]*\.tgz' | sort -r | head -n 1) \
  && DOCKER_URL="https://download.docker.com/linux/static/stable/x86_64/${DOCKER_VERSION}" \
  && echo Docker URL: $DOCKER_URL \
  && curl --silent --show-error --location --fail --retry 3 --output /tmp/docker.tgz "${DOCKER_URL}" \
  && ls -lha /tmp/docker.tgz \
  && tar -xz -C /tmp -f /tmp/docker.tgz \
  && mv /tmp/docker/* /usr/bin \
  && rm -rf /tmp/docker /tmp/docker.tgz \
  && which docker \
  && (docker version || true)

# docker compose
RUN COMPOSE_URL="https://circle-downloads.s3.amazonaws.com/circleci-images/cache/linux-amd64/docker-compose-latest" \
  && curl --silent --show-error --location --fail --retry 3 --output /usr/bin/docker-compose $COMPOSE_URL \
  && chmod +x /usr/bin/docker-compose \
  && docker-compose version

# install dockerize
RUN DOCKERIZE_URL="https://circle-downloads.s3.amazonaws.com/circleci-images/cache/linux-amd64/dockerize-latest.tar.gz" \
  && curl --silent --show-error --location --fail --retry 3 --output /tmp/dockerize-linux-amd64.tar.gz $DOCKERIZE_URL \
  && tar -C /usr/local/bin -xzvf /tmp/dockerize-linux-amd64.tar.gz \
  && rm -rf /tmp/dockerize-linux-amd64.tar.gz \
  && dockerize --version

RUN groupadd --gid 3434 circleci \
  && useradd --uid 3434 --gid circleci --shell /bin/bash --create-home circleci \
  && echo 'circleci ALL=NOPASSWD: ALL' >> /etc/sudoers.d/50-circleci \
  && echo 'Defaults    env_keep += "DEBIAN_FRONTEND"' >> /etc/sudoers.d/env_keep

# BEGIN IMAGE CUSTOMIZATIONS

# cacerts from OpenJDK 9-slim to workaround http://bugs.java.com/view_bug.do?bug_id=8189357
# AND https://github.com/docker-library/openjdk/issues/145
#
# Created by running:
# docker run --rm openjdk:9-slim cat /etc/ssl/certs/java/cacerts | #   aws s3 cp - s3://circle-downloads/circleci-images/cache/linux-amd64/openjdk-9-slim-cacerts --acl public-read
RUN if java -fullversion 2>&1 | grep -q '"9.'; then   curl --silent --show-error --location --fail --retry 3 --output /etc/ssl/certs/java/cacerts        https://circle-downloads.s3.amazonaws.com/circleci-images/cache/linux-amd64/openjdk-9-slim-cacerts;  fi

# Install Maven Version: 3.6.3
RUN curl --silent --show-error --location --fail --retry 3 --output /tmp/apache-maven.tar.gz     http://us.mirrors.quenda.co/apache/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz   && tar xf /tmp/apache-maven.tar.gz -C /opt/   && rm /tmp/apache-maven.tar.gz   && ln -s /opt/apache-maven-* /opt/apache-maven   && /opt/apache-maven/bin/mvn -version

# Install Ant Version: 1.10.7
RUN curl --silent --show-error --location --fail --retry 3 --output /tmp/apache-ant.tar.gz     https://archive.apache.org/dist/ant/binaries/apache-ant-1.10.7-bin.tar.gz   && tar xf /tmp/apache-ant.tar.gz -C /opt/   && ln -s /opt/apache-ant-* /opt/apache-ant   && rm -rf /tmp/apache-ant.tar.gz   && /opt/apache-ant/bin/ant -version

ENV ANT_HOME=/opt/apache-ant

# Install Gradle Version: 5.6.4
RUN curl --silent --show-error --location --fail --retry 3 --output /tmp/gradle.zip     https://services.gradle.org/distributions/gradle-5.6.4-bin.zip   && unzip -d /opt /tmp/gradle.zip   && rm /tmp/gradle.zip   && ln -s /opt/gradle-* /opt/gradle   && /opt/gradle/bin/gradle -version

# Install sbt from https://circle-downloads.s3.amazonaws.com/circleci-images/cache/linux-amd64/sbt-latest.tgz
RUN curl --silent --show-error --location --fail --retry 3 --output /tmp/sbt.tgz https://circle-downloads.s3.amazonaws.com/circleci-images/cache/linux-amd64/sbt-latest.tgz   && tar -xzf /tmp/sbt.tgz -C /opt/   && rm /tmp/sbt.tgz   && /opt/sbt/bin/sbt sbtVersion

# Install openjfx and build-essential
RUN apt-get update     && apt-get install -y --no-install-recommends openjfx     && apt-get install -y build-essential     && rm -rf /var/lib/apt/lists/*

# Update PATH for Java tools
ENV PATH="/opt/sbt/bin:/opt/apache-maven/bin:/opt/apache-ant/bin:/opt/gradle/bin:$PATH"

RUN curl -sL https://deb.nodesource.com/setup_13.x | sudo -E bash -
RUN sudo apt install -y nodejs

# smoke test with path
RUN mvn -version \
  && ant -version \
  && gradle -version \
  && sbt sbtVersion \
  && npm -v

RUN sudo apt-get install libdbus-glib-1-2 \
  && wget -O FirefoxSetup.tar.bz2 "https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=en-US" \
  && sudo tar xjf FirefoxSetup.tar.bz2 \
  && sudo mv firefox /opt \
  && sudo ln -s /opt/firefox/firefox /usr/bin/firefox \
  && firefox -v
# END IMAGE CUSTOMIZATIONS

ENV MYSQL_ALLOW_EMPTY_PASSWORD=true \
    MYSQL_DATABASE=circle_test \
    MYSQL_HOST=127.0.0.1 \
    MYSQL_ROOT_HOST=% \
    MYSQL_USER=root

RUN sudo apt install mysql-server

USER circleci
ENV PATH /home/circleci/.local/bin:/home/circleci/bin:${PATH}

CMD ["/bin/sh"]
