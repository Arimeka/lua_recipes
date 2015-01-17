# lua-nginx-zerogif-counter

## Description

Counting visits by using empty gif.

## Requirements

1. [lua-nginx-module](https://github.com/chaoslawful/lua-nginx-module "lua-nginx-module")
2. [lua-resty-redis](https://github.com/agentzh/lua-resty-redis "lua-resty-redis")

## Usage

Visits counting for two sorted sets in Redis: `host:views:yyyy-mm-dd` and `host:views:total`.

`host:views:yyyy-mm-dd` used to aggregate views to another db.

`host:views:total` used to long-term storing views in Redis.

### Example nginx config

    lua_package_path "/path/to/lua-resty-redis/lib/?.lua;;";
    lua_shared_dict countercache 25m;

    server {
        listen       8089;
        server_name  localhost;
        lua_socket_pool_size 128;

        location /test {
            default_type 'text/plain';

            set $redis_host "127.0.0.1";
            set $redis_port "6379";
            set $redis_db "1";

            content_by_lua_file 'path/to/counter.lua';
        }
    }
