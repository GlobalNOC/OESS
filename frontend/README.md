# Install OESS Using Docker
In this doc is going to cover how to install OESS using Docker for development work.

### Prerequisites
- CentOS 7
-   [Docker](https://docs.docker.com/engine/installation/)
    -   A recent version
 - [Node.js](https://github.com/nvm-sh/nvm)
   - Use NVM to do so
   - Then run `$ nvm install 14`

### Set up dev environment 
Git clone the OESS repository
`$ git clone https://github.com/GlobalNOC/OESS`

cd to the directory 
`$ cd  OESS`

### Update the env.development file
From the `OESS` directory copy `.env.example` to `.env.development`
`$ cp  .env.example env.development`

Update at minimum the following values  
```
MYSQL_ROOT_PASSWORD=
RABBITMQ_DEFAULT_PASS=
MYSQL_USER=
MYSQL_PASS=
RABBITMQ_USER=
RABBITMQ_PASS=
OESS_ADMIN_PASS=
```

### Make a copy and change example.env file
`$ cd frontend/www/new/admin_new`
copy example.env to .env.development  and to .env.production
`$ cp example.env .env.development `
` $ cp example.env .env.production`

Update the following files with your hostname 
`BASE_URL=http://<your_host_name>:8080/oess/`




### Run npn build
Run `npm` from `OESS/frontend/www/new/admin_new`
`$ npm run build`

out put example
```
$ npm run build

> admin_new@1.0.0 build /home/boazraz/OESS/frontend/www/new/admin_new
> parcel build --public-url /oess/new/admin src/index.html

   Built in 9.27s.

dist/App.b0a99e80.js.map       714.31 KB    105ms
dist/App.b0a99e80.js           313.21 KB    6.06s
dist/App.7a5f37e3.css.map        3.84 KB      6ms
dist/App.7a5f37e3.css            2.02 KB    255ms
dist/style.9c2677be.css.map      1.75 KB      6ms
dist/index.html                    961 B     22ms
dist/style.9c2677be.css            906 B    109ms
```
### Run parcel-bundler
From `OESS/frontend/www/new/admin_new`
`$ npm install -g parcel-bundler`

run once 
`$ npm run build`

**If you want auto-reload for web dev**
`$ npm run dev2`

### Run the Makefile 
From the `OESS` directory rum the `Makefile`
`$ make` if all good you can start the docker containers
`$ make start` this command will start the docker containers.
You can check/see the containers by running `$ docker ps` 