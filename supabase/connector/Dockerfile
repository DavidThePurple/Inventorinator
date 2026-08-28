FROM python:3.13-alpine

RUN apk add --no-cache postgresql17-client

WORKDIR /connector
COPY connector/server.py connector/entrypoint.sh ./
COPY migrations ./migrations
RUN chmod 755 entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["./entrypoint.sh"]
