#!/usr/bin/env bash

OPENSTACK_HOST=$1
KEYSTONE_URL=http://${OPENSTACK_HOST}:5000/v3
USER_NAME=$2
PASSWD=$3
DOMAIN_NAME=$4

if [ "$DOMAIN_NAME" == "" ]; then
        echo "usage: ./create_domain HOST_IP ADMIN_USER_NAME PASSWORD NEW_DOMAIN_NAME"
        echo "        HOST_IP: The IP of API"
        echo "        ADMIN_USER_NAME: The admin user name of Default domain"
        echo "        PASSWORD: The admin user password"
        echo "        NEW_DOMAIN_NAME: The name of new domain"
        exit 1
fi

cat > login.json <<EOF
{
    "auth": {
        "identity": {
            "methods": ["password"],
            "password": {
                "user": {
                    "name": "${USER_NAME}",
                    "domain": {
                        "name": "Default"
                    },
                    "password":"${PASSWD}"
                }
            }
        },
        "scope": {
            "domain": {
                "id": "default"
            }
        }
    }
}
EOF
echo "[INFO] Get domain scoped auth token."
DOMAIN_TOKEN=$(curl -i -d @login.json -H "Content-type: application/json" \
 ${KEYSTONE_URL}/auth/tokens | grep X-Subject-Token | grep X-Subject-Token | tail -c 34)

if [ "$DOMAIN_TOKEN" == "" ]; then
        echo "[ERROR] Get domain scoped auth token failed."
        exit 1
fi

echo "[INFO] Create new domain."
cat > domain.json <<EOF
{
    "domain": {
        "description": "Domain description",
        "enabled": true,
        "name": "${DOMAIN_NAME}"
    }
}
EOF

curl -X POST -d @domain.json -H "Content-type: application/json" \
-H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" ${KEYSTONE_URL}/domains > domain.log.json

TARGET_DOMAIN_ID=$(cat domain.log.json | python -c "import sys, json; print json.load(sys.stdin)['domain']['id']")

if [ "$TARGET_DOMAIN_ID" == "" ]; then
        echo "[ERROR] Create new domain failed."
        cat domain.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Create new project under the new domain."
cat > project.json <<EOF
{
    "project": {
        "description": "My new project",
        "enabled": true,
        "name": "Domain_admin_project",
        "domain_id":"${TARGET_DOMAIN_ID}"
    }
}
EOF

curl -X POST -d @project.json \
-H "Content-type: application/json" -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" ${KEYSTONE_URL}/projects > project.log.json

PROJECT_ID=$(cat project.log.json | python -c "import sys, json; print json.load(sys.stdin)['project']['id']")

if [ "$PROJECT_ID" == "" ]; then
        echo "[ERROR] Create new project under the new domain failed."
        cat project.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Create new user under the new domain."
cat > user.json <<EOF
{
    "user": {
        "domain_id": "${TARGET_DOMAIN_ID}",
        "enabled": true,
        "name": "domain_admin",
        "password": "foxconn"
    }
}
EOF

curl -X POST -d @user.json \
-H "Content-type: application/json" -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" ${KEYSTONE_URL}/users > user.log.json

USER_ID=$(cat user.log.json | python -c "import sys, json; print json.load(sys.stdin)['user']['id']")

if [ "$USER_ID" == "" ]; then
        echo "[ERROR] Create new user under the new domain failed."
        cat user.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Get role:domain_admin ID."

curl -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" ${KEYSTONE_URL}/roles?name=domain_admin > domain_admin.log.json

DOMAIN_ADMIN_ROLE_ID=$(cat domain_admin.log.json | python -c "import sys, json; print json.load(sys.stdin)['roles'][0]['id']")

if [ "$DOMAIN_ADMIN_ROLE_ID" == "" ]; then
        echo "[ERROR] Get role:domain_admin ID failed."
        cat domain_admin.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Add user to project as role:domain_admin."
curl -X PUT -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" \
${KEYSTONE_URL}/projects/${PROJECT_ID}/users/${USER_ID}/roles/${DOMAIN_ADMIN_ROLE_ID} > user_to_project.log.json

USER_TO_PROJECT_ROLE=$(curl -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" ${KEYSTONE_URL}/projects/${PROJECT_ID}/users/${USER_ID}/roles | \
python -c "import sys, json; print json.load(sys.stdin)['roles'][0]['id']")

if [ "$DOMAIN_ADMIN_ROLE_ID" != "$USER_TO_PROJECT_ROLE" ]; then
        echo "[ERROR] Add user to project as role:domain_admin failed."
        cat user_to_project.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Add user to domain as role:domain_admin."
curl -X PUT -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" \
${KEYSTONE_URL}/domains/${TARGET_DOMAIN_ID}/users/${USER_ID}/roles/${DOMAIN_ADMIN_ROLE_ID} > user_to_domain.log.json

USER_TO_DOMAIN_ROLE=$(curl -H "X-Auth-Token: ${DOMAIN_TOKEN:0:32}" \
${KEYSTONE_URL}/domains/${TARGET_DOMAIN_ID}/users/${USER_ID}/roles | \
python -c "import sys, json; print json.load(sys.stdin)['roles'][0]['id']")

if [ "$DOMAIN_ADMIN_ROLE_ID" != "$USER_TO_DOMAIN_ROLE" ]; then
        echo "[ERROR] Add user to domain as role:domain_admin failed."
        cat user_to_domain.log.json | python -m json.tool
        exit 1
fi

echo "[INFO] Test: create new domain and its admin user and project success"
