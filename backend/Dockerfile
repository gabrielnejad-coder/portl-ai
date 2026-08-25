FROM node:24-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev

COPY tsconfig.json ./
COPY src ./src
COPY test ./test

ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

CMD ["node", "--experimental-strip-types", "src/index.ts"]
