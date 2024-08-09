
######################################################
#### Helper functions and variable initialization ####
######################################################

# Load packages
source("packages.R")

# Read in list of budget items to look up in data
items <- readLines("items.csv")
items <- gsub('^"|"$', '', items)

# List of budget items with redundant language
repeats <- c("Service and Business Income", "Non-Current Liabilities", "Expenditures",
             "Tax Revenue", "Non-Tax Revenue", "Revenue", "Property, Plant, and Equipment",
             "Non-Current Assets", "Business Income", "Payables", "Receipts from Printing and Publication",
             "Receipts from business/service income")

# Construct list of col names for budget report df
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

# Read in PDF budget report and turn into text
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
  
  # If that doesn't work, try OCR
  if(grepl("^\\s*$", text)) {
    text <- sapply(1:pdf_info(path)$pages,
           \(x) ocr(image_read(pdf_render_page(path, page = x, dpi = 600)))) |> 
      paste(collapse = "\n")
  }
  
  # Clean text
  text <- gsub("\n", " ", text)
  text <- gsub("[()]", "", text)
  text <- gsub("\\s+", " ", text)
  text <- gsub("2022|2021", "", text)
  text <- trimws(text)
  
  return(text)
}

# Code to initialize region x year specific vars
initialize <- function(path) {
  lgu <<- gsub("-", " ", str_match(path, "/\\d{4}/[A-Za-z\\s]+/(.*)-Annual-Audit")[2])
  if(grepl("NCR", path) & grepl("2022", path)) {
    regular_exp <<- ".*?\\(?([0-9]{4,}(?:,[0-9]{3})*(?:\\.[0-9]+)?)\\)?(?=\\s)"
  }
  if(grepl("Bangsamoro", path) & grepl("2022", path)) {
    lgu <<- gsub("[-_]", "", str_match(path, "/\\d{4}/[A-Za-z\\s]+/-?(.*)2022")[2])
    regular_exp <<- "(?:(?![a-zA-Z]{3}).)*?\\(?([0-9,]+\\.[0-9]{2})\\)?\\s"
    if(is.na(lgu)) {
      lgu <<- gsub("[-_]", "", str_match(path, "/\\d{4}/[A-Za-z\\s]+/-?(.*)Audit_Report.pdf"))
    }
    lgu <<- gsub("([^A-Z])([A-Z])", "\\1 \\2", lgu)
  }
  if(grepl("Bicol", path) & grepl("2022", path)) {
    regular_exp <<- "(?:(?![=a-zA-Z]{3}).)*?\\(?([0-9,]+\\.[0-9]{2})\\)?[Pp\\|\\s]"
  }
}

# Find a line item in the budget text and return its corresponding amount
extract_number <- function(text, target_string, regular_exp) {
  # Regular expression to match the target string and the number pattern with optional parentheses
  pattern <- paste0(target_string, regular_exp)
  
  # Change regex to match budget items with repeat language
  pattern <- ifelse(target_string %in% repeats,
                    paste0("(?<!Total |Tax |of |Other |- )", pattern),
                    pattern)
  
  # Extract only the number from the match
  number <- str_match(text, pattern)[,2]
  
  # Return the result as a number without commas
  return(as.numeric(gsub(",", "", number)))
}

# Read in one budget report file and return observation
clean <- function(path) {
  initialize(path)
  text <- ifelse(grepl(".pdf", path, ignore.case = TRUE), read_.pdf(path),
                 read_.xlsx(path))
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
    new <- data.frame(extract_number(text, string, regular_exp))
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
  return(df)
}

# File name expressions that indicate a budget
audit_lang <- c("Part1-FS", "Part1-Financial_Statements", "Audit_Report.pdf") |> 
  paste(collapse = "|")

##################
#### Run code ####
##################

# Set directory from which to make budget data
directory <- "/Budgets/2022/Bangsamoro"

# Get file paths of budgets in directory
paths <- list.files(paste0(getwd(), directory), recursive = TRUE) |> 
  map(\(x) paste0(paste0(directory, "/"), x)) |> 
  as.matrix() |> 
  as.data.frame()
names(paths) <- "path"
paths <- paths |> filter(grepl(audit_lang, path) == TRUE)

# Create data frame of budget reports
tictoc::tic()
budgets <- NULL
for (i in 1:nrow(paths)) {
  if(!grepl("zip", paths[i,])) {
    budgets <- build(budgets, obs = clean(substring(paths[i,], 2)))
    }
  }
tictoc::toc()
