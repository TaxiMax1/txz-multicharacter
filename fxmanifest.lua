fx_version 'cerulean'
game 'gta5'
author 'TXZ Scripts - Taxzyyy'
version '1.0'
lua54 'yes'
discord 'https://discord.gg/GhKgp6yWtJ'

shared_scripts { 
  '@ox_lib/init.lua',
  'locales/*.lua',
  'shared/*.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/*.lua',
}

client_scripts {
  "client/*.lua"
}

ui_page 'web/build/index.html'

files { 
  'web/build/index.html', 
  'web/build/**/*.*'
}

escrow_ignore {
  'config.lua',
  'shared/exports.lua',
  'locales/*.lua',
}