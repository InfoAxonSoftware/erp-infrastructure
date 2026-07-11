FROM node:20-alpine

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev=false
COPY . .
RUN npx prisma generate && npm prune --omit=dev

ENV NODE_ENV=production PORT=5000
EXPOSE 5000
CMD ["npm", "start"]
