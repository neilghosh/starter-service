FROM node:20-alpine

WORKDIR /app

ARG COMMIT_SHA=local
ARG DEPLOY_TAG=default
ENV COMMIT_SHA=${COMMIT_SHA}
ENV DEPLOY_TAG=${DEPLOY_TAG}
ENV PORT=8080

COPY package.json ./
COPY src ./src

USER node
EXPOSE 8080

CMD ["node", "src/server.js"]
