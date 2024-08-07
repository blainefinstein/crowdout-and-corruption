library(readxl)
library(purrr)
library(tidyverse)
library(TAF)
library(NLP)
library(stringr)
library(pdftools)

######################################################
#### Helper functions and variable initialization ####
######################################################

# reads each sheet of the excel into a list
read_helper <- function(path) {
  sheets <- excel_sheets(path)
  return(map(sheets, \(x) read_excel(path, sheet = x)))
}

# Read in list of budget items to look up in data
items <- readLines("items.csv")
items <- gsub('^"|"$', '', items)

# List of budget items with redundant language
repeats <- c("Service and Business Income", "Non-Current Liabilities", "Expenditures",
             "Tax Revenue", "Non-Tax Revenue", "Revenue", "Property, Plant, and Equipment",
             "Non-Current Assets")

# construct list of col names for budget report df
cols <- c("lgu", "region", "year", "city") |> 
  append(items) |>
  sapply(function(x) {
    x <- tolower(x)                      # Convert to lower case
    x <- gsub(" ", "_", x)               # Replace spaces with underscores
    x <- gsub(",_", "_", x)              # Replace ",_" with "_"
    x <- gsub("/", "_", x)               # Replace "/" with "_"
    x <- gsub("_-_", "_", x)             # Replace "_-_" with "_"
    return(x)
  })

# Read in excel budget report and turn into text
read_.xlsx <- function(path) {
  # Get the names of all sheets
  sheet_names <- excel_sheets(path)
  
  # Initialize an empty string to store the final result
  final_str <- ""
  
  # Loop through each sheet and append its content to the final string
  for (sheet in sheet_names) {
    df <- read_excel(path, sheet = sheet)
    df_str <- capture.output(write.table(df, row.names = FALSE, sep = " ", quote = FALSE))
    df_str <- paste(df_str, collapse = "\n")
    final_str <- paste(final_str, paste("Sheet:", sheet), df_str, sep = " ")
  }
  
  # Print the final concatenated string
  return(final_str)
}

# Read PDF into character string
read_.pdf <- function(path) {
  # Read each page of PDf into list
  pages <- tryCatch({
    pdf_text(path)
  }, error = function(err) {
    message("Error: ", conditionMessage(err))
    return("")
  })
  
  # Combine all text from list into one string
  text <- ""
  for(i in 1:length(pages)) {
    text <- paste(text, pages[i])
  }
  
  # Clean text
  text <- gsub("\n", " ", text)
  text <- gsub("[()]", "", text)
  text <- gsub("\\s+", " ", text)
  text <- trimws(text)
  
  return(text)
}

# Find a line item in the budget text and return its corresponding amount
extract_number <- function(text, target_string) {
  # Regular expression to match the target string and the number pattern with optional parentheses
  pattern <- paste0(target_string, ".*?\\(?([0-9]{4,}(?:,[0-9]{3})*(?:\\.[0-9]+)?)\\)?(?=\\s)")
  
  # Change regex to match budget items with repeat language
  pattern <- ifelse(target_string %in% repeats, paste0("(?<!Total |Tax |of |Other |- )",
                                                       pattern), pattern)
  
  # Extract only the number from the match
  number <- str_match(text, pattern)[,2]
  
  # Return the result as a number without commas
  return(as.numeric(gsub(",", "", number)))
}

# Code to initialize province x year specific vars
capture <- function(path) {
  if(grepl("NCR", path) & grepl("2022", path)) {
    return(gsub("-", " ", str_match(path, "/\\d{4}/[A-Za-z\\s]+/(.*)-Annual-Audit")[2]))
  }
  if(grepl("Bangsamoro", path) & grepl("2022", path)) {
    lgu <- gsub("[-_]", "", str_match(path, "/\\d{4}/[A-Za-z\\s]+/-?(.*)2022")[2])
    if(is.na(lgu)) {
      lgu <- gsub("[-_]", "", str_match(path, "/\\d{4}/[A-Za-z\\s]+/-?(.*)Audit_Report.pdf")[2])
    }
    return(gsub("([^A-Z])([A-Z])", "\\1 \\2", lgu))
  }
}

# Read in one budget report file and return observation
clean <- function(path) {
  text <- ifelse(grepl(".pdf", path, ignore.case = TRUE), read_.pdf(path),
                 read_.xlsx(path))
  lgu <- capture(path)
  region <- str_match(path, "Budgets/\\d{4}/([A-Za-z\\s]+)/")[2]
  year <- str_match(path, "Budgets/(\\d{4})/")[2]
  city <- ifelse(grepl("city", path, ignore.case = TRUE), 1, 0)
  res <- data.frame(
    lgu = lgu,
    region = region,
    year = year,
    city = city
  )
  
  # Loop over line items and build observation out of budget report
  for(string in items) {
    new <- data.frame(extract_number(text, string))
    names(new) <- tolower(string)
    res <- cbind(res, new)
  }
  
  # Column name repair
  colnames(res) <- gsub(" ", "_", colnames(res))
  colnames(res) <- gsub("_[:][_]", "_", colnames(res))
  colnames(res) <- gsub(",_", "_", colnames(res))
  colnames(res) <- gsub("/", "_", colnames(res))
  colnames(res) <- gsub("_-_", "_", colnames(res))
  
  return(res)
}

# Add one budget to df of budget reports
build <- function(df = NULL, obs) {
  # If null, build new df
  if(is.null(df)) {
    df <- data.frame(matrix(ncol = length(cols), nrow = 1))
    names(df) <- cols
    for (name in names(df)) {
      if(name %in% names(obs) && is.na(df[[name]])) {
        df[[name]] <- obs[[name]]
      }
    }
  } else {
    # If municipality name already in df, add to same row
    if(obs$lgu %in% df$lgu) {
      i <- which(df == obs$lgu)
      for (name in names(df)) {
        if(name %in% names(obs) && is.na(df[[name]][i])) {
          df[[name]][i] <- obs[[name]]
        }
      }
    } else {
      # If municipality name not already in df, add to new row
      new_row <- data.frame(matrix(ncol = length(cols), nrow = 1))
      names(new_row) <- cols
      for (name in names(df)) {
        if(name %in% names(obs) && is.na(new_row[[name]])) {
          new_row[[name]] <- obs[[name]]
        }
      }
      df <- rbind(df, new_row)
    } 
  }
  
  return(df)
}

# file name expressions that indicate a budget
audit_lang <- c("Part1-FS", "Part1-Financial_Statements")
pattern <- paste(audit_lang, collapse="|")

##################
#### Run code ####
##################

# Set directory from which to make budget data
directory <- "/Budgets/2022/NCR"

# Get unzipped directories (every other file)
places <- list.files(paste0(getwd(), directory)) |> 
  map(\(x) paste0(paste0(directory, "/"), x))
places <- places[seq_along(places) %% 2 != 0]

# Map over unzipped directories to get budget report file paths (if have zips)
paths <- places |> 
  map_df(function(x) {
    out <- list.files(paste0(getwd(), x)) |> 
      map_df(\(y) data.frame(path = paste0(paste0(x, "/"), y))) |> 
        filter(grepl(pattern, path) == TRUE)
    return(budgets = out)
  }) |> rbind.data.frame()

# Turn list into data frame (no zip directories)
paths <- as.data.frame(as.matrix(places))

# Index at which to start reading
start <- 1

# Create data frame of budget reports
tictoc::tic()
budgets <- build(obs = clean(substring(paths[start,], 2)))
for (i in (start + 1):nrow(paths)) {
    budgets <- build(budgets, obs = clean(substring(paths[i,], 2)))
  }
tictoc::toc()

