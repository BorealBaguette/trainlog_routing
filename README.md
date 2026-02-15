This repo contains the router used by: https://github.com/simfr24/Trainlog to route vehicles

### Setup instructions:

1. If using windows then configure WSL - https://learn.microsoft.com/en-us/windows/wsl/install
2. Download these dependencies:
	a. sudo apt install make
	b. sudo apt install osmium-tool (if this doesn't work run remember to run: sudo apt-get update)
3. Ensure docker is running: https://docs.docker.com/desktop/wsl/
4. Run "make train" (or other vehicle type), this will takes ages to download OSM data and process it
5. After processing any files in the "world" directory can be deleted to save space

### Running:

1. Run "make serve-train" (or other vehicle type)
2. At https://trainlog.me/ start making a train route as normal, before clicking "submit" open the network view in your browsers setting.
3. After clicking submit search through the requests to find one to the deployed router. This should look like: "https://trainlog.me/forwardRouting/train/route/v1/train/-1.4621381,53.3783713;-1.548621,53.794414?overview=false&alternatives=true&steps=true"
4. Replace the first section with your local router - for example: "localhost:5000/route/v1/train/-1.4621381,53.3783713;-1.548621,53.794414?overview=false&alternatives=true&steps=true"
5. Copy the Polyline from the geometry value to a site like: https://valhalla.github.io/demos/polyline/?unescape=true&polyline6=false to view it

When finished the router can be stopped using: Docker stop train_routing

If you need to re-install the router delete everything in the Output folder