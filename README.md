# ROBLOX Pipeline
Example project that automates template/place modification and publishing for Roblox games

## Setup
1. Fork repository
2. Create Developer API key as shown [here](https://create.roblox.com/docs/en-us/cloud/guides/usage-place-publishing#publish-a-place) ([documentation](https://create.roblox.com/docs/en-us/cloud/auth/api-keys#create-api-keys))
3. Add the following repository secrets (or environment secrets if you prefer
   multiple pipelines):
```bash
API_KEY="..."
PLACE_ID="..."
UNIVERSE_ID="..."
```
4. **Read the contents of** the initialisation script, then run it:
```bash
# cat/bat/less/more ./initialise
./initialise
```
5. Push changes to `src/`
