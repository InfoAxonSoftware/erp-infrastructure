FROM nginx:1.25-alpine

RUN apk add --no-cache curl

# Remove the default configuration so our templates take full control
RUN rm -f /etc/nginx/conf.d/default.conf

EXPOSE 80 443

# ENTRYPOINT and CMD are inherited from the base image.
# The base image automatically processes /etc/nginx/templates/*.template
# files via envsubst at startup, outputting to /etc/nginx/conf.d/.
