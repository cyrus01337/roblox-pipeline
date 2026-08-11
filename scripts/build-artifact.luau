-- TODO: Cache all service paths for future processing instead of performing the
-- same process necessary to retrieve them N times
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

type Leaf = {
    ["$path"]: string?,

    [string]: Leaf,
}

type Tree = {
    ["$className"]: string?,

    [string]: Leaf,
}

type Configuration = {
    name: string,
    tree: Tree,
}

type PathToServiceMap = {
    [string]: { string },
}

type Instance = roblox.Instance

local function walkFilesRecursively(path: string): { string }
    local paths = {}

    if not fs.isDir(path) then
        return {}
    end

    for _, objectName in fs.readDir(path) do
        local objectPath = `{path}/{objectName}`

        if fs.isFile(objectPath) then
            table.insert(paths, objectPath)

            continue
        end

        for _, walkedPath in walkFilesRecursively(objectPath) do
            table.insert(paths, walkedPath)
        end
    end

    return paths
end

local function findPath(leaf: Leaf): (string?, string?)
    local pathFound = leaf["$path"]

    if pathFound then
        return "", pathFound
    end

    for serviceName, potentialPathOrLeaf in leaf do
        if typeof(potentialPathOrLeaf) == "table" then
            local nestedServiceName, nestedPathFound = findPath(potentialPathOrLeaf)

            if not nestedPathFound then
                continue
            end

            return if #nestedServiceName > 0 then nestedServiceName else serviceName, nestedPathFound
        end
    end

    return nil, nil
end

local function createPathToServiceMap(tree: Tree, ancestors: { string }?): PathToServiceMap
    local defaultAncestors = if ancestors ~= nil then ancestors else {}
    local map = {}

    for key, leaf in tree do
        if key == "$className" or key == "$path" then
            continue
        end

        local serviceName = key
        local pathFound = leaf["$path"]

        if not pathFound then
            for path, nestedAncestors in createPathToServiceMap(leaf, { serviceName }) do
                map[path] = nestedAncestors
            end

            continue
        end

        if #defaultAncestors == 0 then
            map[pathFound] = { serviceName }
        else
            map[pathFound] = { table.unpack(defaultAncestors), serviceName }
        end
    end

    return map
end

local function findServiceNameFromPath(path: string): string?
    -- local pathSegments = path:split("/")
    -- local resolvablePath = `{pathSegments[1]}/{pathSegments[2]}`

    -- for potentialServiceName, leaf in PROJECT_CONFIGURATION.tree do
    --     if potentialServiceName:sub(1) == "$" or typeof(leaf) ~= "table" then
    --         continue
    --     end

    --     local pathFound = leaf["$path"]
    --     local nestedServiceName, nestedPathFound = findPath(leaf)

    --     if
    --         pathFound and pathFound:sub(0, #resolvablePath) == resolvablePath
    --         or nestedPathFound and nestedPathFound:sub(#resolvablePath) == resolvablePath
    --     then
    --         return potentialServiceName
    --     elseif not pathFound and nestedPathFound and nestedPathFound:sub(0, #resolvablePath) == resolvablePath then
    --         return nestedServiceName
    --     end
    -- end

    -- return nil
end

local function normaliseScriptFileName(fileName: string): { string }
    local name, centerOrTail = table.unpack(fileName:split("."))

    if centerOrTail == "luau" then
        return { name, "ModuleScript" }
    elseif centerOrTail == "client" then
        return { name, "LocalScript" }
    elseif centerOrTail == "server" then
        return { name, "Script" }
    end

    error(`Invalid filename provided: {fileName}`)
end

local function findBaseScript(path: string, location: Instance): Instance?
    local currentLocation = location
    local fragments = path:split("/")
    local fileName = fragments[#fragments]
    local baseScriptName, expectedInstanceType = table.unpack(normaliseScriptFileName(fileName))

    for _, name in path:split("/") do
        local newLocationFound = currentLocation:FindFirstChild(name)

        if not newLocationFound then
            -- TODO: Add a way to differentiate between this function giving nil
            -- because the location doesn't exist, and the function giving nil
            -- because the base script doesn't exist
            return nil
        end

        currentLocation = newLocationFound
    end

    local baseScriptFound = currentLocation:FindFirstChild(baseScriptName)

    if not (baseScriptFound or baseScriptFound:IsA(expectedInstanceType)) then
        return nil
    end

    return baseScriptFound
end

local function createInGamePath(service: Instance, pathSegments: { string }): Instance
    local currentLocation = service

    for _, segment in pathSegments do
        local newLocationFound = currentLocation:FindFirstChild(segment)

        if newLocationFound then
            currentLocation = newLocationFound

            continue
        end

        newLocationFound = roblox.Instance.new("Folder")
        newLocationFound.Name = segment
        newLocationFound.Parent = currentLocation
        currentLocation = newLocationFound
    end

    return currentLocation
end

local function main(...): ()
    local START_TIME = os.clock()
    local projectConfiguration: Configuration = serde.decode("json", fs.readFile("default.project.json"))
    local pathToServiceMap = createPathToServiceMap(projectConfiguration.tree)
    local template = roblox.deserializePlace(fs.readFile("template.rbxl"))

    print(`Building artifact in {process.cwd}\n`)

    -- for _, filePath in walkFilesRecursively("src") do
    --     local pathSegments = filePath:split("/")
    --     local resolvablePath = ""

    --     for position = 3, #pathSegments do
    --         resolvablePath ..= `{pathSegments[position]}`

    --         if position < #pathSegments then
    --             resolvablePath ..= "/"
    --         end
    --     end

    --     local serviceNameFound = findServiceNameFromPath(filePath)

    --     if not serviceNameFound then
    --         error(`Unable to locate service for {filePath}`)
    --     elseif serviceNameFound == "StarterPlayerScripts" then
    --         serviceNameFound = "StarterPlayer"
    --     end

    --     local service = template:GetService(serviceNameFound)
    --     local baseScriptFound = findBaseScript(resolvablePath, service)

    --     if baseScriptFound then
    --         print("Found base script for", filePath, "at", baseScriptFound)
    --     end

    --     if not baseScriptFound then
    --         print("Creating in-game path for", filePath)

    --         local fileName = table.remove(pathSegments, table.find(pathSegments, pathSegments[#pathSegments]))
    --         print(fileName, normaliseScriptFileName(fileName))
    --         local baseScriptName, expectedInstanceType = table.unpack(normaliseScriptFileName(fileName))
    --         baseScriptFound = roblox.Instance.new(expectedInstanceType)
    --         baseScriptFound.Name = baseScriptName
    --         baseScriptFound.Parent = createInGamePath(service, pathSegments)
    --     end

    --     baseScriptFound.Source = fs.readFile(filePath)
    -- end
    for _, filePath in walkFilesRecursively("src") do
        local pathSegments = filePath:split("/")
        local fileName = pathSegments[#pathSegments]
        local baseScriptName, expectedScriptType = table.unpack(normaliseScriptFileName(fileName))

        print("Processing", filePath)

        for path, serviceMap in pathToServiceMap do
            local startsWithPath = filePath:sub(1, #path) == path

            if not startsWithPath then
                continue
            end

            -- Creating a copy is necessary as modifying the table reference
            -- causes subsequent cycles to receive the same table but altered,
            -- which needs to be avoided
            local mutableServiceMap = table.clone(serviceMap)
            local serviceName = table.remove(mutableServiceMap, 1)
            local currentLocation = template:GetService(serviceName)

            for _, location in mutableServiceMap do
                local newLocationFound = currentLocation:FindFirstChild(location)

                if not newLocationFound then
                    newLocationFound = roblox.Instance.new("Folder")
                    newLocationFound.Name = location
                    newLocationFound.Parent = currentLocation

                    print("Created new folder:", newLocationFound:GetFullName())
                end

                currentLocation = newLocationFound
            end

            local baseScriptFound = currentLocation:FindFirstChild(fileName)

            if not baseScriptFound then
                baseScriptFound = roblox.Instance.new(expectedScriptType)
                baseScriptFound.Name = baseScriptName
                baseScriptFound.Parent = currentLocation

                print(`Created new {expectedScriptType}: {baseScriptFound:GetFullName()}`)
            end

            baseScriptFound.Source = fs.readFile(filePath)

            print("Mapped", filePath, "to", baseScriptFound:GetFullName(), `({expectedScriptType})\n`)

            break
        end
    end

    fs.writeFile("artifact.rbxl", roblox.serializePlace(template))

    local durationInMilliseconds = math.floor((os.clock() - START_TIME) * 1000)

    print(`Successfully built artifact, took {durationInMilliseconds}ms`)
end

main()
