library(pdftools)
library(stringr)

file <- "Al-Barka2022_Audit_Report copy.pdf"
pages <- pdf_text(file)
text <- ""

for(i in 1:length(pages)) {
  text <- paste(text, pages[i])
}

# Clean text for easy (ish) number extraction
clean_text <- function(t) {
  # Replace every newline character with a space
  t <- gsub("\n", " ", t)
  
  # Remove every open or closed parenthesis
  t <- gsub("[()]", "", t)
  
  # Replace any number of spaces with a single space
  text <- gsub("\\s+", " ", text)
  
  # Trim leading and trailing spaces
  text <- trimws(text)
  
  return(t)
}

# Find a line item in the budget text and return its corresponding amount
extract_number <- function(input_string, target_string) {
  # Regular expression to match the target string and the number pattern with optional parentheses
  pattern <- paste0(target_string, ".*?\\(?([0-9,]+\\.[0-9]{2})\\)?\\s")
  
  # Use str_extract to find the first match
  match <- str_extract(input_string, pattern)
  
  # Extract only the number from the match
  number <- str_match(match, "\\(?([0-9,]+\\.[0-9]{2})\\)?")[,2]
  
  # Return the result as a number without commas
  return(as.numeric(gsub(",", "", number)))
}

clean_text(text)
extract_number(text, "Cash and Cash Equivalents")
