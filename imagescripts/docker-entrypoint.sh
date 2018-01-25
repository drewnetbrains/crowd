#!/bin/bash
#
# A helper script for ENTRYPOINT.
#
# If first CMD argument is 'jira', then the script will start jira
# If CMD argument is overriden and not 'jira', then the user wants to run
# his own process.

set -o errexit

function processCrowdProxySettings() {
  if [ -n "${CROWD_PROXY_NAME}" ]; then
    xmlstarlet ed -P -S -L --insert "//Connector[not(@proxyName)]" --type attr -n proxyName --value "${CROWD_PROXY_NAME}" ${CROWD_INSTALL}/apache-tomcat/conf/server.xml
  fi

  if [ -n "${CROWD_PROXY_PORT}" ]; then
    xmlstarlet ed -P -S -L --insert "//Connector[not(@proxyPort)]" --type attr -n proxyPort --value "${CROWD_PROXY_PORT}" ${CROWD_INSTALL}/apache-tomcat/conf/server.xml
  fi

  if [ -n "${CROWD_PROXY_SCHEME}" ]; then
    xmlstarlet ed -P -S -L --insert "//Connector[not(@scheme)]" --type attr -n scheme --value "${CROWD_PROXY_SCHEME}" ${CROWD_INSTALL}/apache-tomcat/conf/server.xml
  fi

if [ -n "${CROWD_PROXY_SECURE}" ]; then
    xmlstarlet ed -P -S -L --insert "//Connector[not(@secure)]" --type attr -n secure --value "${CROWD_PROXY_SECURE}" ${CROWD_INSTALL}/apache-tomcat/conf/server.xml
  fi
}

if [ -n "${CROWD_DELAYED_START}" ]; then
  sleep ${CROWD_DELAYED_START}
fi

# Download Atlassian required config files from s3
/usr/bin/aws s3 cp s3://fathom-atlassian-ecs/crowd/${CROWD_CONFIG} ${CROWD_HOME}/shared/${CROWD_CONFIG}

# Pull Atlassian secrets from parameter store
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWSREGION=${AZ::-1}

DATABASE_ENDPOINT=$(aws ssm get-parameters --names "${ENVIRONMENT}.atlassian.rds.db_host" --region ${AWSREGION} --with-decryption --query Parameters[0].Value --output text)
DATABASE_USER=$(aws ssm get-parameters --names "${ENVIRONMENT}.atlassian.rds.db_user" --region ${AWSREGION} --with-decryption --query Parameters[0].Value --output text)
DATABASE_PASSWORD=$(aws ssm get-parameters --names "${ENVIRONMENT}.atlassian.rds.password" --region ${AWSREGION} --with-decryption --query Parameters[0].Value --output text)
DATABASE_NAME=${DATABASE_NAME}

/bin/sed -i -e "s/DATABASE_ENDPOINT/$DATABASE_ENDPOINT/" \
            -e "s/DATABASE_USER/$DATABASE_USER/" \
            -e "s/DATABASE_PASSWORD/$DATABASE_PASSWORD/" \
            -e "s/DATABASE_NAME/$DATABASE_NAME/" shared/${CROWD_CONFIG}

# End of aws section

processCrowdProxySettings

# If there are any certificates that should be imported to the JVM Keystore,
# import them.  Note that KEYSTORE is defined in the Dockerfile
if [ -d /var/atlassian/crowd/certs ]; then
  for c in /var/atlassian/crowd/certs/* ; do
    echo Found certificate $c, importing to JVM keystore
    keytool -trustcacerts -keystore $KEYSTORE -storepass changeit -noprompt -importcert -file $c || :
  done
fi

if [ "$1" = 'crowd' ] || [ "${1:0:1}" = '-' ]; then
  exec su-exec crowd /home/crowd/launch.sh
else
  exec su-exec crowd "$@"
fi
