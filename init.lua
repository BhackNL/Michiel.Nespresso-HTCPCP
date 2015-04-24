tmr.delay(500000) -- Wait 500ms
available = false

-- Setup GPIO
gpio.mode(1, gpio.OUTPUT) -- Espresso
gpio.write(1, gpio.LOW)

gpio.mode(2, gpio.OUTPUT) -- Lungo
gpio.write(2, gpio.LOW)

gpio.mode(3, gpio.INT, gpio.PULLUP)
gpio.trig(3, "up", function(level) -- Rising edge means LED turns off
    available = false
    tmr.stop(0)
    
    tmr.alarm(0, 1250000, 0, function() -- Assuming the LED has a frequency of 1Hz
        available = true
    end)
end)

-- Setup TCP server
srv = net.createServer(net.TCP)
srv:listen(80, function(conn)
    conn:on("receive", function(conn, data)
        local headers = getHeaders(data)
        local _, _, verb = data:find("(%w+) ")
    
        if verb == "GET" then
            handleGet(conn, headers)
        elseif verb == "BREW" or verb == "POST" then
            handleBrew(conn, headers)
        end
    end)
end)

-- Request handlers
function handleGet(conn, headers)
    local responseHeaders = {["Content-Type"] = "text/html"}

    file.open("index.html", "r")
    endResponse(conn, 200, "OK", responseHeaders, file.read())
    file.close()
end

function handleBrew(conn, headers)
    pin = 0
    
    if not ready then
        endResponse(conn, 503, "Service Unavailable", nil, "The coffee pot is not available right now.")
        return
    end
    
    if headers["Accept-Additions"] then
        endResponse(conn, 406, "Not Acceptable", nil, "This coffee pot does not allow additions.")
        return
    end
    
    if headers["X-Coffee-Type"] == "espresso" then
        pin = 1
    elseif headers["X-Coffee-Type"] == "lungo" then
        pin = 2
    else
        endResponse(conn, 400, "Bad Request", nil, "Please provide a valid X-Coffee-Type (espresso, lungo).")
        return
    end
    
    gpio.write(pin, gpio.HIGH)
    tmr.delay(250000)
    gpio.write(pin, gpio.LOW)

    local responseHeaders = {["Content-Type"] = "message/coffeepot"}
    endResponse(conn, 200, "OK", responseHeaders, "start")
end

-- HTTP utilities
function getHeaders(data)
    isFirst = true
    headers = {}

    for line in data:gmatch("%C+") do    
        if isFirst then
            isFirst = false
        else
            _, _, key, value = line:find("(.+): (.+)")
            headers[key] = value
        end
    end

    return headers
end

function endResponse(conn, statusCode, statusMessage, headers, data)
    conn:send("HTTP/1.0 " .. statusCode .. " " .. statusMessage .. "\r\n")

    if headers then
        for k, v in pairs(headers) do conn:send(k .. ": " .. v .. "\r\n") end
    end

    conn:send("\r\n")
    if data then conn:send(data) end
    
    conn:close()
end
