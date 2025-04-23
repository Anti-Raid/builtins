--- Parses a string to seconds
---
--- E.g. `1 hour` -> 3600, `1h` -> 3600, `1 hour 30 minutes` -> 5400, `1h30m` -> 5400, `1h30min 1 seconds` -> 3600+1800+1=5401
local function parseToSeconds(input: string): number
    --print("Parsing " .. input)
    local currentNumbers: {string} = {}
    local currentUnits: {string} = {}

    local subbed = input:gsub("%s+", "")
    local within: "StartPoint" | "Number" | "Unit" = "StartPoint"
    for char in subbed:gmatch(".") do
        if tonumber(char) then
            if within == "StartPoint" or within == "Unit" then
                --print("At within = " .. within .. ", adding new number with first char " .. char)
                currentNumbers[#currentNumbers+1] = char
                within = "Number"
            elseif within == "Number" then
                --print("At within = " .. within .. ", adding char " .. char .. " to number")
                currentNumbers[#currentNumbers] = currentNumbers[#currentNumbers] .. char
            end
        else
            if within == "StartPoint" or within == "Number" then
                --print("At within = " .. within .. ", adding new unit with first char " .. char)
                currentUnits[#currentUnits+1] = char
                within = "Unit"
            elseif within == "Unit" then
                --print("At within = " .. within .. ", adding char " .. char .. " to unit")
                currentUnits[#currentUnits] = currentUnits[#currentUnits] .. char
            end
        end
    end 

    local totalSeconds = 0
    for i, numberStr in currentNumbers do
        --print("Number: " .. numberStr .. ", Unit: " .. currentUnits[i])

        local number = tonumber(numberStr)

        if not number then
            error("Invalid number: " .. numberStr)
        end

        local unit = currentUnits[i]
        if unit == "s" or unit == "sec" or unit == "secs" or unit == "second" or unit == "seconds" then
            totalSeconds += number
        elseif unit == "m" or unit == "min" or unit == "mins" or unit == "minute" or unit == "minutes" then
            totalSeconds += number * 60
        elseif unit == "h" or unit == "hs" or unit == "hr" or unit == "hrs" or unit == "hour" or unit == "hours" then
            totalSeconds += number * 3600
        elseif unit == "d" or unit == "ds" or unit == "day" or unit == "days" then
            totalSeconds += number * 86400
        elseif not unit then
            -- No unit, assume seconds
            totalSeconds += number
        else 
            error("Invalid unit: " .. tostring(unit))
        end
    end

    return totalSeconds
end

assert(parseToSeconds("1 hour") == 3600, "Expected 3600, got " .. tostring(parseToSeconds("1 hour")))
assert(parseToSeconds("1h") == 3600, "Expected 3600, got " .. tostring(parseToSeconds("1h")))
assert(parseToSeconds("1 hour 30 minutes") == 5400, "Expected 5400, got " .. tostring(parseToSeconds("1 hour 30 minutes")))
assert(parseToSeconds("1h30m") == 5400)
assert(parseToSeconds("1h30min 1 seconds") == 5401)

return parseToSeconds