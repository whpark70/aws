#!/usr/bin/bash

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
$(aws sts assume-role \
--role-arn arn:aws:iam::532805286864:role/AdminRole \
--role-session-name cdk-sesion-1 \
--query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
--output text))