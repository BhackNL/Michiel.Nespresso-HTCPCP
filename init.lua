available = true

-- Setup GPIO
gpio.mode(5, gpio.INT, gpio.PULLUP)
gpio.trig(5, "up", function(level) -- Rising edge means LED turns off
    available = false
    tmr.stop(0)
    
    tmr.alarm(0, 1250, 0, function()
        print("I - Pot available")
        available = true
    end)
end)

gpio.mode(1, gpio.OUTPUT) -- Lungo (GPIO 5)
gpio.write(1, gpio.HIGH)

gpio.mode(2, gpio.OUTPUT) -- Espresso (GPIO 4)
gpio.write(2, gpio.HIGH)

srv = net.createServer(net.TCP)
srv:listen(80, function(conn)
    conn:on("receive", function(conn, data)
        isVerb = true
		verb = nil
        headers = {}
    
        for line in data:gmatch("%C+") do    
            if isVerb then
				_, _, verb = line:find("(%w+) ")
                isVerb = false
            else
                _, _, key, value = line:find("(.+): (.+)")
                headers[key] = value
            end
        end
    
        if verb == "GET" then
            handleGet(conn, headers)
        elseif verb == "BREW" or verb == "POST" then
            handleBrew(conn, headers)
        end
    end)
end)

print("I - Pot booted")

function handleGet(conn, headers)
    print("I - Serving web page")
    local responseHeaders = {["Content-Type"] = "text/html"}

    file.open("index.html", "r")
    endResponse(conn, 200, "OK", responseHeaders, file.read())
    file.close()
end

function handleBrew(conn, headers)
    if not available then
        print("E - Cannot brew, pot unavailable")
        endResponse(conn, 503, "Service Unavailable", nil, "The coffee pot is not available right now.")
        return
    end
    
    if headers["Accept-Additions"] then
        print("E - Additions not accepted")
        endResponse(conn, 406, "Not Acceptable", nil, "This coffee pot does not accept additions.")
        return
    end
    
    pin = 0
    if headers["X-Coffee-Variation"] == "espresso" then
        pin = 2
    elseif headers["X-Coffee-Variation"] == "lungo" then
        pin = 1
    else
        print("E - Coffee variation invalid or not specified")
        endResponse(conn, 400, "Bad Request", nil, "Please provide a valid X-Coffee-Variation header (espresso | lungo).")
        return
    end

    print("I - Brewing some " .. headers["X-Coffee-Variation"])

    local responseHeaders = {["Content-Type"] = "message/coffeepot",
                             ["Safe"] = "yes"}
    endResponse(conn, 200, "OK", responseHeaders, "start")

    gpio.write(pin, gpio.LOW)
    tmr.delay(500000)
    gpio.write(pin, gpio.HIGH)
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
