FROM node:20-alpine

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev=false
COPY server ./server
RUN npx prisma generate --schema=server/prisma/schema.prisma
RUN npm prune --omit=dev

ENV NODE_ENV=production PORT=5000
EXPOSE 5000
CMD ["node", "server/index.js"]
