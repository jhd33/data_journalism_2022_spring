library(tidyverse)
library(lubridate)
library(rvest)
library(janitor)

urls <- read_csv("url_csvs/ncaa_mens_lacrosse_teamurls_2023.csv") %>% pull(3)

season = "2023"

root_url <- "https://stats.ncaa.org"

matchstatstibble = tibble()

matchstatsfilename <- paste0("data/ncaa_mens_lacrosse_matchstats_", season, ".csv")

for (i in urls){
  
  schoolpage <- i %>% read_html()
  
  if (str_detect(i, "org_id=282")) { # special case for Hobart
    schoolfull = 'Hobart Statesmen'
  } else {
    schoolfull <- schoolpage %>% html_nodes(xpath = '//*[@id="contentarea"]/fieldset[1]/legend/a[1]') %>% html_text()
  }
  
  message <- paste0("Adding ", schoolfull)
  
  print(message)
  
  schoolpage %>% html_nodes(xpath = '/html/body/div[2]/fieldset[1]/legend/a[1]') %>% html_text()
  
  matches <- schoolpage %>% html_nodes(xpath = '//*[@id="game_breakdown_div"]/table') %>% html_table()
  
  # doesn't handle postponed games right now (Hobart has one)
  # doesn't retain W/L, need to calculate that from score.

  matches <- matches[[1]] %>% slice(3:n()) %>% row_to_names(row_number = 1) %>% clean_names() %>% 
    remove_empty(which = c("cols")) %>% 
    mutate_all(na_if,"") %>% 
    fill(c(date, result)) %>% 
    mutate_at(vars(5:26),  replace_na, '0') %>% 
    mutate(date = mdy(date), home_away = case_when(grepl("@",opponent) ~ "Away", TRUE ~ "Home"), opponent = gsub("@ ","",opponent)) %>%
#    mutate(WinLoss = case_when(grepl("L", result) ~ "Loss", grepl("W", result) ~ "Win", grepl("T", result) ~ "Draw"), 
#           result = gsub("L ", "", result), result = gsub("W ", "", result), result = gsub("T ", "", result)) %>% 
    separate(result, into=c("score", "overtime"), sep = " \\(") %>% 
    separate(score, into=c("home_score", "visitor_score")) %>% 
#    rename(result = WinLoss) %>% 
    mutate(result = is.character(NA)) %>% # placeholder for now
    mutate(team = schoolfull) %>% 
    mutate(overtime = gsub(")", "", overtime)) %>% 
    select(date, team, opponent, home_away, result, home_score, visitor_score, overtime, everything()) %>% 
    clean_names() %>% 
    mutate_at(vars(-date, -opponent, -home_away, -result, -team), ~str_replace(., "/", "")) %>% 
    mutate_at(vars(-date, -team, -opponent, -home_away, -result, -overtime, -g_min), as.numeric)
  
  teamside <- matches %>% filter(opponent != "Defensive Totals")
  
  opponentside <- matches %>% filter(opponent == "Defensive Totals") %>% select(-opponent, -home_away) %>% rename_with(.cols = 7:30, function(x){paste0("defensive_", x)})
  
  joinedmatches <- inner_join(teamside, opponentside, by = c("date", "team", "result", "home_score", "visitor_score", "overtime"))
  
  tryCatch(matchstatstibble <- bind_rows(matchstatstibble, joinedmatches),
           error = function(e){NA})
  
  
  Sys.sleep(2)
}

teams <- matchstatstibble %>% 
  group_by(team) %>% 
  summarise(team)


write_csv(matchstatstibble, matchstatsfilename)

