local exit, print, header, add_js, arg = os.exit, print, header, add_js, arg
local require, pairs, debug, tinsert = require, pairs, debug, table.insert
local gmatch, tsort = string.gmatch, table.sort
local Spore = require [[Spore]]
local json = require [[json]]

module [[ophal.modules.zophin]]

function menu()
  items = {}
  items.zophin = {
    title = [[Welcome to Zophin]],
    page_callback = [[page]],
  }
  items['twitter'] = {
    title = [[Twitter backend]],
    page_callback = [[twitter_router]],
  }
  items['youtube'] = {
    title = [[Youtube backend]],
    page_callback = [[youtube_data]],
  }
  return items
end

function page()
  return [[<!-- Application source. -->
  <script data-main="/modules/zophin/app/config" src="/modules/zophin/assets/js/libs/require.js"></script>
  <script type="text/javascript" src="/modules/zophin/assets/js/libs/swfobject.js"></script>
  <!-- Main container. -->
  <div role="main" id="zophin"></div>]]
end

function twitter_router()
  local output = [[]]
  if arg(2) == [[data]] then
    output = twitter_data(arg(1))
  else
    output = twitter_check(arg(1))
  end

  header([[content-type]], [[application/json; charset=utf-8]])
  print(output)
  exit()
end

-- Stupid tagger implementation...
function termextract(messages)
  local terms = {}
  local words = {}
  local count = 0

  -- Extract and count words
  for _, message in pairs(messages) do
    for w in message.text:gmatch [[%S+]] do
      w = w:lower()
      if words[w] == nil then
        words[w] = {
          word = w,
          count = 0,
        }
      end
      words[w].count = words[w].count + 1
    end
  end

  -- Merge hashtags and increase its counter by 5
  for word in pairs(words) do
    if word:sub(1, 1) == [[#]] then
      w = word:sub(2)
      if words[w] == nil then
        words[w] = {
          word = w,
          count = 0,
        }
      end
      words[w].count = words[w].count + words[word].count * 5
    end
  end

  -- Remove user mentions, hashtags     
  for word, v in pairs(words) do
    if word:sub(1, 1) == [[@]] or word:sub(1, 1) == [[#]] or word:sub(1, 4) == [[http]] then
      -- ignore
    elseif word:len() < 5 then
      -- ignore
    else
      -- add term
      count = count + 1
      terms[#terms +1] = v
      -- truncate to 256 terms
      if count >= 256 then
        break
      end
    end
  end

  -- Sort
  tsort(terms, function (a, b)
    return a.count > b.count
  end)

  return terms
end

function twitter_data(userid)
  local twitter, res, data, messages, lastid

  twitter = Spore.new_from_lua{
    base_url = [[http://api.twitter.com/1/statuses/user_timeline.json]],
    methods = {
      lookup = {
        path = [[]],
        method = [[GET]],
        required_params = {[[user_id]], [[count]], [[trim_user]], [[include_rts]]},
      }
    }
  }
  twitter:enable [[Format.JSON]]
  res = twitter:lookup{
    user_id = userid,
    count = 200,
    trim_user = true,
    include_rts = true,
  }

  messages = res.body

  if res.status == 200 then
    if #messages > 0 then
      return json.encode(termextract(messages))
    else
      header([[status]], 400)
      print [[Vixe: usuário não tem mensagens :P]]
      exit()
    end
  else
    header([[status]], 500)
    print [[Vixe: API do Twitter baleiou/miguelou na carga de tweets.]]
    exit()
  end

  return "data"
end

function twitter_check(username)
  local twitter, res, data

  twitter = Spore.new_from_lua{
    base_url = [[https://api.twitter.com/1/users/lookup.json]],
    methods = {
      lookup = {
        path = [[]],
        method = [[GET]],
        required_params = {[[screen_name]]},
      }
    }
  }
  twitter:enable [[Format.JSON]]
  res = twitter:lookup{
    screen_name = username,
  }

  data = res.body

  if res.status == 200 then
    if res.body[1].protected then
      return json.encode{
        message = [[User has its tweets protected.]],
        code = [[00]],
      }
    end
    return json.encode{
      user_id = data[1].id_str,
      user_name = data[1].name,
      user_avatar = data[1].profile_image_url,
      user_protected = data[1].protected,
    }
  elseif res.status == 404 then
    if data.errors then
      header([[status]], 500)
      print [[Vixe: errors!.]]
      exit()
      -- TODO
      -- Read res.request.env.errors
      --~ data.errors.filter(function(e, i, a){
        --~ if (e.code == 34) {
          --~ res.send('Eita: nenhum usuário encontrado.', 404);
        --~ }
      --~ })
    end
  else
    header([[status]], 500)
    print [[Vixe: API do Twitter baleio/miguelou na busca por usuários.]]
    exit()
  end
end


function youtube_data()
  local youtube, res, media
  local response = {}
  local count = 0

  youtube = Spore.new_from_lua{
    base_url = [[https://gdata.youtube.com/feeds/api/videos]],
    methods = {
      lookup = {
        path = [[]],
        method = [[GET]],
        required_params = {[[alt]], [[q]], [[v]], [[orderby]]},
      }
    }
  }
  youtube:enable [[Format.JSON]]
  res = youtube:lookup{
    alt = [[json]],
    q = arg(1) .. arg(2),
    v = 2,
    orderby = [[published]],
  }

  data = res.body

  if res.status == 200 then
    if data.feed.entry then
      for _, entry in pairs(data.feed.entry) do
        count = count + 1
        media = entry['media$group']
        tinsert(response, {
          video_id = media['yt$videoid']['$t'],
          video_title = media['media$title']['$t'],
          video_length = media['yt$duration']['seconds'],
          video_des = media['media$description']['$t']
        })
        -- truncate to 5 videos
        if count > 4 then
          break
        end
      end
      header([[content-type]], [[application/json; charset=utf-8]])
      print(json.encode(response))
      exit()
    else
      header([[status]], 500)
      print [[Vixe: problemas com acentuação (ou nenhum resultado).]]
      exit()
    end
  end
end
