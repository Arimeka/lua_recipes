-- Connecting to Redis
local redis = require "resty.redis"
local red = redis:new()

-- Divides string into substrings based on a delimiter, returning an array of these substrings.
function string:split(sep)
  local sep, fields = sep or ":", {}
  local pattern = string.format("([^%s]+)", sep)
  self:gsub(pattern, function(c) fields[#fields+1] = c end)
  return fields
end

-- Get second to end of day (string fotmat: yyyy-mm-dd hh:mm:ss)
function string:seconds_to_end_of_day()
  local datetime = self:split(' ')
  local time = datetime[2]:split(':')

  return (86400 - tonumber(time[1])*60*60 + tonumber(time[2])*60 + tonumber(time[3]))
end

-- Write data from shared memory to Redis
function write_to_redis(cache, host)
  -- Flush expired keys from shared memory
  cache:flush_expired()
  -- Blosking write to Redis
  cache:set('block', 1)

  -- Set timeoute to Redis
  red:set_timeout(1000) -- 1 sec

  -- Configure connection to Redis
  local redis_host = ngx.var.redis_host
  if ngx.var.redis_host == nil then redis_host = 'localhost' end

  local redis_port = ngx.var.redis_port
  if ngx.var.redis_port == nil then redis_port = 6379 end

  local redis_db = ngx.var.redis_db
  if ngx.var.redis_db == nil then redis_db = 1 end

  -- Trying to sonnect to Redis
  local ok, err = red:connect(redis_host, redis_port)
  if not ok then
    ngx.log(ngx.ERR, "failed to connect: ", err)
    return
  end
  red:select(redis_db)

  -- Get list of keys in shared memory (default 1024)
  -- This is a blocking operation, so, be careful
  local keys = cache:get_keys()

  -- Get valuse of keys and write to Redis
  for _,value in pairs(keys) do
    local k = value:split('/')
    if k[2] ~= nil then
      local redis_key = k[1]
      local record = k[2]
      local views = cache:get(value)

      -- Write to total views
      if redis_key == host..':views:total' then
        red:zincrby(redis_key, views, record)
      -- Write to today views
      elseif redis_key == host..':views:today' then
        red:zincrby(redis_key, views, record)
        red:expire(redis_key, ngx.localtime():seconds_to_end_of_day())
      end
      -- Delete key after write
      cache:delete(value)
    end
  end
  -- Remove blocking
  cache:delete('block')
end

-- Write data to shared memory
function write_counter(redis_key, record, host)
  local locked
  local lock_ttl = 3 -- 3 sec

  -- Shared memory
  local cache = ngx.shared.countercache
  -- Record key
  local local_key = redis_key..'/'..record

  -- Flush expired keys from shared memory
  cache:flush_expired()

  -- Check write to redis
  locked = cache:get('block')

  -- Get key from shared memory
  local chunk = cache:get(local_key)
  -- If we have key
  if chunk then
    -- Increment
    cache:incr(local_key, 1)
  else
    -- Else, set key and set expire to end of day
    cache:set(local_key, 1, ngx.localtime():seconds_to_end_of_day())
  end

  -- If write to redis not blocked
  if locked == nil then
    -- Start write to Redis
    write_to_redis(cache, host)
    -- After this, lock write to Redis for lock_ttl sec
    cache:set('block', 1, lock_ttl)
  end
end

-- If request have http_referer, continue
if ngx.var.http_referer then
  local uri
  local host
  -- Get host and path from http_referer
  host, uri = ngx.var.http_referer:match('https?://([^/]+)(.*)')

  -- If we find host and path, continue
  if host ~= nil and uri ~= nil and uri ~= '' then
    -- Key for total views
    local total = host..':views:total'
    -- Key for aggreagte views
    local today =  host..':views:today'

    -- Write views to shared memory
    write_counter(today, uri, host)
    write_counter(total, uri, host)

    -- For low visited host you don't need to use shared memory
    -- and can write data directly to Redis
    -- red:set_timeout(1000)

    -- local redis_host = ngx.var.redis_host
    -- if ngx.var.redis_host == nil then redis_host = 'localhost' end

    -- local redis_port = ngx.var.redis_port
    -- if ngx.var.redis_port == nil then redis_port = 6379 end

    -- local redis_db = ngx.var.redis_db
    -- if ngx.var.redis_db == nil then redis_db = 1 end

    -- local ok, err = red:connect(redis_host, redis_port)
    -- if not ok then
    --   ngx.log(ngx.ERR, "failed to connect: ", err)
    --   return
    -- end
    -- red:select(redis_db)

    -- red:zincrby(total, 1, uri)
    -- red:zincrby(today, 1, uri)
    -- red:expire(today, ngx.localtime():seconds_to_end_of_day())
  end

  -- Save conection pool for 10 sec
  red:set_keepalive(10000, 128)
end

-- Send 0.gif to client
ngx.say(ngx.decode_base64('R0lGODlhAQABAPAAAAAAAAAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=='))
