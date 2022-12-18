library(shiny)
library(leaflet)
library(RColorBrewer)
library(dplyr)

# WARNING schedule really big; requires ~3GB and ~30 sec to load
schedule <- read.csv('main_schedule.csv')

colnames(schedule)[5] <- "lat"
colnames(schedule)[6] <- "lon"

unique_stops <- schedule[!duplicated(schedule$stop_id), ]  # unique 
tmp_routes <- unique_stops %>% group_by(route_id) %>% summarise(route_count = n(), .groups = 'drop')
tmp_routes_ordered <- tmp_routes[order(tmp_routes$route_count, decreasing = TRUE), ]
routes <- c("All", tmp_routes_ordered$route_id)

# visit_num contains number of occurrences of that stop as next_stop which is equal to number of 
# planned visits of this stop
visit_num_df <- schedule %>% group_by(next_stop_id) %>% summarise(visit_num=n(), .groups = 'drop')
visit_num_df <- visit_num_df[visit_num_df$visit_num != max(visit_num_df$visit_num),] # maximum visit count is > 2mil so it's dropped because it must be bug
visit_num_df['visit_num'] = log10(visit_num_df$visit_num)

main_table <- merge(unique_stops, visit_num_df, by.x="stop_id", by.y="next_stop_id")

max_visit <- as.integer(max(main_table$visit_num))
min_visit <- as.integer(min(main_table$visit_num))
date_from <- min(main_table$departure_time)
date_to <- max(main_table$departure_time)


ui <- fluidPage(
  titlePanel("Europe rails"),
  sidebarLayout(
    sidebarPanel(
      sliderInput("range", "log10(number of visits)", min_visit, max_visit,
                  value = c(min_visit, max_visit), step = 0.1),
      dateRangeInput("date_range", "Date range", start = date_from, end = date_to, min = date_from, max = date_to, format = "dd-mm-yyyy"),
      selectInput("routes", "Route id's", choices = routes, selected = routes[1], multiple = TRUE)
    ),
    mainPanel(
      leafletOutput("map", width="100%", height=800),
    )
  )
)

server <- function(input, output, session) {
  # creating filtered data frame according to App input
  filtered_stops <- reactive({
    time_filter <- main_table[main_table$departure_time >= input$date_range[1] & main_table$departure_time <= input$date_range[2], ]
    visit_filter <- time_filter[time_filter$visit_num >= input$range[1] & time_filter$visit_num <= input$range[2], ]
    if ("All" %in% input$routes) {
      visit_filter
    } else {
      visit_filter[visit_filter$route_id %in% input$routes, ]
    }
  })
  
  # get vector of colors in color space for all values
  colorpal <- reactive({
    colorNumeric("Spectral", main_table$visit_num)
  })
  
  # rendering leaflet map
  output$map <- renderLeaflet({
    leaflet(main_table) %>% addTiles() %>%
      fitBounds(~min(lon), ~min(lat), ~max(lon), ~max(lat))
  })
  
  # run every time input was changed
  observe({
    pal <- colorpal()
    leafletProxy("map", data = filtered_stops()) %>%
      clearShapes() %>%
      clearControls() %>%
      addCircles(radius = 10, color = ~pal(visit_num), popup = ~paste("Visits: ", 10^visit_num), fillOpacity = 0.9) %>%
      addLegend("bottomright", pal = pal, values = ~visit_num,
                title = "log10(visit number)", opacity = 1)
  })

}

shinyApp(ui, server)