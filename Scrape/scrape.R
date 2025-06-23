library(RSelenium)
library(netstat)
library(readr)
library(tidyverse)
library(purrr)

# specify Firefox profile w desired download directory
file_path <- paste0(getwd(), "/Budgets/2022")
fprof <- makeFirefoxProfile(list(browser.download.dir = file_path,
                                 browser.download.folderList = 2L,
                                 browser.download.manager.showWhenStarting =
                                   FALSE,
                                 browser.helperApps.neverAsk.openFile =
                                   "text/csv",
                                 browser.helperApps.neverAsk.saveToDisk =
                                   "text/csv"))

# Start a Selenium server with the custom Firefox profile
rD <- rsDriver(browser = "firefox", verbose = FALSE, port = free_port(),
               extraCapabilities = fprof)
remDr <- rD[["client"]]

# navigate to download url
remDr$navigate("https://www.coa.gov.ph/reports/annual-audit-reports/aar-local-government-units")

# alter subsequent code to navigate to alternate portions of directory,
# or hand click in selenium browser

# go to year
remDr$findElement(using = "link text", value = "2022")$clickElement()

# find province
remDr$findElement(using = "css selector", value = 
                               ".open .collapsed:nth-child(1) span")$clickElement()

# find zip reports (no PDFs)
elemCity <- remDr$findElements(using = "css selector", value = ".zip .wpfd-file-link")

# set timeout (doesn't work)
remDr$setImplicitWaitTimeout(type = "script", milliseconds = 30000)

# download all files in directory and write csv of URLs to machine
map_df(elemCity, function(x) {
  x$clickElement()
  Sys.sleep(30)
  elemURL <- remDr$findElement(using = "link text", value =
                                 "Download")
  elemURL$clickElement()
  URL <- toString(elemURL$getElementAttribute("href"))
  remDr$findElement(using = "class name", value = "wpfd-close")$clickElement()
  return(data.frame(url = URL))
}) |> 
  write_csv(file = "URLs_Mindanao_2022")

# combine URLs into single file
URLs <- list.files(paste0(getwd(), "/URLs/2022")) |> 
  map(\(x) paste0("URLs/2022/", x)) |> 
  map_df(read_csv) |>
  rbind.data.frame()
write_csv(URLs, file = "URLs_2022")

# stop server
rD$server$stop()