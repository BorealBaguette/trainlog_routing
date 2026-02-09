.PRECIOUS: %.pbf
.SECONDARY: $(COUNTRIES_PBF)

$(shell mkdir -p world output output/stats filtered_ferry filtered_train filtered_bus filtered_aerialway world/africa world/asia world/australia-oceania world/central-america world/europe world/north-america world/south-america)

# Common variables for train, ferry, aerialway
WANTED_COUNTRIES := $(shell grep -v "\#" countries.wanted)
COUNTRIES_PBF := $(addsuffix -latest.osm.pbf,$(addprefix world/,$(WANTED_COUNTRIES)))

# Bus has its own country list
BUS_WANTED_COUNTRIES := $(shell grep -v "\#" bus_countries.wanted)
BUS_COUNTRIES_PBF := $(addsuffix -latest.osm.pbf,$(addprefix world/,$(BUS_WANTED_COUNTRIES)))
BUS_FILTERED_PBF := $(patsubst world/%,filtered_bus/%,$(BUS_COUNTRIES_PBF))

# All unique region paths (for KML downloads)
ALL_REGIONS := $(sort $(WANTED_COUNTRIES) $(BUS_WANTED_COUNTRIES))
ALL_KMLS := $(addsuffix .kml,$(addprefix kml/,$(ALL_REGIONS)))

# ── KML download (one per region, cached) ────────────────────────────────
kml/%.kml:
	@mkdir -p $(dir $@)
	@wget -q -N -O $@ https://download.geofabrik.de/$*.kml 2>/dev/null || echo "<kml/>" > $@

download-kmls: $(ALL_KMLS)
	@echo "All KMLs downloaded ($(words $(ALL_KMLS)) files)"

# ── Download ──────────────────────────────────────────────────────────────
world/%.osm.pbf:
	@START=$$(date +%s); \
	wget -N -q --show-progress -P $(@D)/ https://download.geofabrik.de/$*.osm.pbf; \
	END=$$(date +%s); \
	SIZE=$$(stat -c%s "$@" 2>/dev/null || echo 0); \
	echo '{"step":"download","file":"$*","duration_s":'$$((END-START))',"size_bytes":'$$SIZE',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/download_$(subst /,_,$*).json

# ── Filter ────────────────────────────────────────────────────────────────
filtered_ferry/%.osm.pbf: world/%.osm.pbf params/ferry_filter.params
	@mkdir -p filtered_ferry
	@START=$$(date +%s); \
	osmium tags-filter --expressions=params/ferry_filter.params $< -o $@ --overwrite; \
	END=$$(date +%s); \
	SIZE=$$(stat -c%s "$@" 2>/dev/null || echo 0); \
	echo '{"step":"filter","type":"ferry","file":"$*","duration_s":'$$((END-START))',"size_bytes":'$$SIZE',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/filter_ferry_$(subst /,_,$*).json

filtered_train/%.osm.pbf: world/%.osm.pbf params/train_filter.params
	@mkdir -p filtered_train
	@START=$$(date +%s); \
	osmium tags-filter --expressions=params/train_filter.params $< -o $@ --overwrite; \
	END=$$(date +%s); \
	SIZE=$$(stat -c%s "$@" 2>/dev/null || echo 0); \
	echo '{"step":"filter","type":"train","file":"$*","duration_s":'$$((END-START))',"size_bytes":'$$SIZE',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/filter_train_$(subst /,_,$*).json

filtered_aerialway/%.osm.pbf: world/%.osm.pbf params/aerialway_filter.params
	@mkdir -p filtered_aerialway
	@START=$$(date +%s); \
	osmium tags-filter --expressions=params/aerialway_filter.params $< -o $@ --overwrite --progress -v; \
	END=$$(date +%s); \
	SIZE=$$(stat -c%s "$@" 2>/dev/null || echo 0); \
	echo '{"step":"filter","type":"aerialway","file":"$*","duration_s":'$$((END-START))',"size_bytes":'$$SIZE',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/filter_aerialway_$(subst /,_,$*).json

filtered_bus/%.osm.pbf: world/%.osm.pbf params/bus_filter.params
	@mkdir -p $(dir $@)
	@START=$$(date +%s); \
	osmium tags-filter --expressions=params/bus_filter.params $< -o $@ --overwrite; \
	END=$$(date +%s); \
	SIZE=$$(stat -c%s "$@" 2>/dev/null || echo 0); \
	echo '{"step":"filter","type":"bus","file":"$*","duration_s":'$$((END-START))',"size_bytes":'$$SIZE',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/filter_bus_$(subst /,_,$*).json

# ── Merge ─────────────────────────────────────────────────────────────────
output/filtered_ferry.osm.pbf: $(subst world,filtered_ferry,$(COUNTRIES_PBF))
	@START=$$(date +%s); \
	osmium merge $^ -o $@ --overwrite; \
	END=$$(date +%s); \
	SIZE=$$(stat -c%s "$@" 2>/dev/null || echo 0); \
	echo '{"step":"merge","type":"ferry","duration_s":'$$((END-START))',"size_bytes":'$$SIZE',"input_count":'$(words $^)',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/merge_ferry.json

output/filtered_train.osm.pbf: $(subst world,filtered_train,$(COUNTRIES_PBF))
	@START=$$(date +%s); \
	osmium merge $^ -o $@ --overwrite; \
	END=$$(date +%s); \
	SIZE=$$(stat -c%s "$@" 2>/dev/null || echo 0); \
	echo '{"step":"merge","type":"train","duration_s":'$$((END-START))',"size_bytes":'$$SIZE',"input_count":'$(words $^)',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/merge_train.json

output/filtered_aerialway.osm.pbf: $(subst world,filtered_aerialway,$(COUNTRIES_PBF))
	@START=$$(date +%s); \
	osmium merge $^ -o $@ --overwrite; \
	END=$$(date +%s); \
	SIZE=$$(stat -c%s "$@" 2>/dev/null || echo 0); \
	echo '{"step":"merge","type":"aerialway","duration_s":'$$((END-START))',"size_bytes":'$$SIZE',"input_count":'$(words $^)',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/merge_aerialway.json

output/filtered_bus.osm.pbf: $(BUS_FILTERED_PBF)
	@START=$$(date +%s); \
	osmium merge $^ -o $@ --overwrite; \
	END=$$(date +%s); \
	SIZE=$$(stat -c%s "$@" 2>/dev/null || echo 0); \
	echo '{"step":"merge","type":"bus","duration_s":'$$((END-START))',"size_bytes":'$$SIZE',"input_count":'$(words $^)',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/merge_bus.json

# ── OSRM build (with phase tracking in lock file) ────────────────────────
output/filtered_ferry.osrm: output/filtered_ferry.osm.pbf profiles/ferry.lua
	@echo extracting > output/.ferry_building.lock
	@START=$$(date +%s); \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-extract -p /opt/host/profiles/ferry.lua /opt/host/$<; \
	echo partitioning > output/.ferry_building.lock; \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-partition /opt/host/$<; \
	echo customizing > output/.ferry_building.lock; \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-customize /opt/host/$<; \
	END=$$(date +%s); \
	echo '{"step":"osrm_build","type":"ferry","duration_s":'$$((END-START))',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/osrm_ferry.json
	@rm -f output/.ferry_building.lock

output/filtered_train.osrm: output/filtered_train.osm.pbf profiles/train.lua
	@echo extracting > output/.train_building.lock
	@START=$$(date +%s); \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-extract -p /opt/host/profiles/train.lua /opt/host/$<; \
	echo partitioning > output/.train_building.lock; \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-partition /opt/host/$<; \
	echo customizing > output/.train_building.lock; \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-customize /opt/host/$<; \
	END=$$(date +%s); \
	echo '{"step":"osrm_build","type":"train","duration_s":'$$((END-START))',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/osrm_train.json
	@rm -f output/.train_building.lock

output/filtered_aerialway.osrm: output/filtered_aerialway.osm.pbf profiles/aerialway.lua
	@echo extracting > output/.aerialway_building.lock
	@START=$$(date +%s); \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-extract -p /opt/host/profiles/aerialway.lua /opt/host/$<; \
	echo partitioning > output/.aerialway_building.lock; \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-partition /opt/host/$<; \
	echo customizing > output/.aerialway_building.lock; \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-customize /opt/host/$<; \
	END=$$(date +%s); \
	echo '{"step":"osrm_build","type":"aerialway","duration_s":'$$((END-START))',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/osrm_aerialway.json
	@rm -f output/.aerialway_building.lock

output/filtered_bus.osrm: output/filtered_bus.osm.pbf profiles/bus.lua
	@echo extracting > output/.bus_building.lock
	@START=$$(date +%s); \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-extract -p /opt/host/profiles/bus.lua /opt/host/$<; \
	echo partitioning > output/.bus_building.lock; \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-partition /opt/host/$<; \
	echo customizing > output/.bus_building.lock; \
	docker run --rm -t -v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 osrm-customize /opt/host/$<; \
	END=$$(date +%s); \
	echo '{"step":"osrm_build","type":"bus","duration_s":'$$((END-START))',"timestamp":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
		> output/stats/osrm_bus.json
	@rm -f output/.bus_building.lock

# ── Top-level build targets (with phase tracking) ────────────────────────
bus:
	@echo downloading > output/.bus_building.lock
	@$(MAKE) --no-print-directory $(BUS_COUNTRIES_PBF)
	@echo filtering > output/.bus_building.lock
	@$(MAKE) --no-print-directory $(BUS_FILTERED_PBF)
	@echo merging > output/.bus_building.lock
	@$(MAKE) --no-print-directory output/filtered_bus.osm.pbf
	@$(MAKE) --no-print-directory output/filtered_bus.osrm

train:
	@echo downloading > output/.train_building.lock
	@$(MAKE) --no-print-directory $(COUNTRIES_PBF)
	@echo filtering > output/.train_building.lock
	@$(MAKE) --no-print-directory $(subst world,filtered_train,$(COUNTRIES_PBF))
	@echo merging > output/.train_building.lock
	@$(MAKE) --no-print-directory output/filtered_train.osm.pbf
	@$(MAKE) --no-print-directory output/filtered_train.osrm

aerialway:
	@echo downloading > output/.aerialway_building.lock
	@$(MAKE) --no-print-directory $(COUNTRIES_PBF)
	@echo filtering > output/.aerialway_building.lock
	@$(MAKE) --no-print-directory $(subst world,filtered_aerialway,$(COUNTRIES_PBF))
	@echo merging > output/.aerialway_building.lock
	@$(MAKE) --no-print-directory output/filtered_aerialway.osm.pbf
	@$(MAKE) --no-print-directory output/filtered_aerialway.osrm

ferry:
	@echo downloading > output/.ferry_building.lock
	@$(MAKE) --no-print-directory $(COUNTRIES_PBF)
	@echo filtering > output/.ferry_building.lock
	@$(MAKE) --no-print-directory $(subst world,filtered_ferry,$(COUNTRIES_PBF))
	@echo merging > output/.ferry_building.lock
	@$(MAKE) --no-print-directory output/filtered_ferry.osm.pbf
	@$(MAKE) --no-print-directory output/filtered_ferry.osrm

all: train ferry bus aerialway

# ── Serve targets ─────────────────────────────────────────────────────────
serve-train: train
	-@docker stop train_routing > /dev/null 2>&1 && docker rm train_routing > /dev/null 2>&1 ||:
	docker run --restart always --name train_routing -t -d -p 5000:5000 \
		-v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 \
		osrm-routed --algorithm mld /opt/host/output/filtered_train.osrm

serve-ferry: ferry
	-@docker stop ferry_routing > /dev/null 2>&1 && docker rm ferry_routing > /dev/null 2>&1 ||:
	docker run --restart always --name ferry_routing -t -d -p 5001:5000 \
		-v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 \
		osrm-routed --algorithm mld /opt/host/output/filtered_ferry.osrm

serve-bus: bus
	-@docker stop bus_routing > /dev/null 2>&1 && docker rm bus_routing > /dev/null 2>&1 ||:
	docker run --restart always --name bus_routing -t -d -p 5002:5000 \
		-v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 \
		osrm-routed --algorithm mld /opt/host/output/filtered_bus.osrm

serve-aerialway: aerialway
	-@docker stop aerialway_routing > /dev/null 2>&1 && docker rm aerialway_routing > /dev/null 2>&1 ||:
	docker run --restart always --name aerialway_routing -t -d -p 5003:5000 \
		-v $$(pwd):/opt/host ghcr.io/project-osrm/osrm-backend:v6.0.0 \
		osrm-routed --algorithm mld /opt/host/output/filtered_aerialway.osrm

serve-all: serve-train serve-aerialway serve-ferry serve-bus

# ── Health server (no pip install, no external deps) ──────────────────────
serve-health: download-kmls
	-@docker stop health_server > /dev/null 2>&1 && docker rm health_server > /dev/null 2>&1 ||:
	docker run --restart always --name health_server -t -d -p 5010:5010 \
		-v $$(pwd):/opt/host \
		-v /var/run/docker.sock:/var/run/docker.sock \
		python:3.11-slim \
		python /opt/host/health.py

# ── Clean targets ─────────────────────────────────────────────────────────
clean-bus:
	-@rm -f output/.bus_building.lock
	-@rm output/filtered_bus* > /dev/null 2>&1 ||:
	-@rm -r filtered_bus/* > /dev/null 2>&1 ||:
	-@rm output/stats/*bus* > /dev/null 2>&1 ||:

clean-train:
	-@rm -f output/.train_building.lock
	-@rm output/filtered_train* > /dev/null 2>&1 ||:
	-@rm filtered_train/* > /dev/null 2>&1 ||:
	-@rm output/stats/*train* > /dev/null 2>&1 ||:

clean-aerialway:
	-@rm -f output/.aerialway_building.lock
	-@rm output/filtered_aerialway* > /dev/null 2>&1 ||:
	-@rm filtered_aerialway/* > /dev/null 2>&1 ||:
	-@rm output/stats/*aerialway* > /dev/null 2>&1 ||:

clean-ferry:
	-@rm -f output/.ferry_building.lock
	-@rm output/filtered_ferry* > /dev/null 2>&1 ||:
	-@rm filtered_ferry/* > /dev/null 2>&1 ||:
	-@rm output/stats/*ferry* > /dev/null 2>&1 ||:

clean-downloads:
	-@rm -r world/* > /dev/null 2>&1 ||:

clean-kmls:
	-@rm -r kml/* > /dev/null 2>&1 ||:

clean-health:
	-@docker stop health_server > /dev/null 2>&1 && docker rm health_server > /dev/null 2>&1 ||:

# refresh-all does NOT touch health_server
refresh-all:
	$(MAKE) clean-bus clean-train clean-aerialway clean-ferry
	$(MAKE) serve-all

# Also restart health
refresh-everything:
	$(MAKE) clean-bus clean-train clean-aerialway clean-ferry
	$(MAKE) serve-all serve-health

clean: clean-bus clean-train clean-aerialway clean-ferry clean-downloads clean-kmls clean-health
