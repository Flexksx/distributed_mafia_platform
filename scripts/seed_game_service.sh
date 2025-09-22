#!/usr/bin/env bash

# Seed Game Service Database via HTTP API
# This script creates sample game data by calling the REST API endpoints

set -e

# Configuration
GAME_SERVICE_URL="${GAME_SERVICE_URL:-http://localhost:3001}"
USER_SERVICE_URL="${USER_SERVICE_URL:-http://localhost:3000}"
NUM_LOBBIES=6

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Helper function to generate random data
generate_lobby_name() {
    local adjectives=("Shadow" "Midnight" "Crimson" "Silent" "Twisted" "Dark" "Ancient" "Mysterious" "Haunted" "Forbidden")
    local nouns=("Manor" "Village" "Town" "Estate" "Haven" "Sanctuary" "Castle" "Fortress" "Chambers" "Hall")
    local adj=${adjectives[$RANDOM % ${#adjectives[@]}]}
    local noun=${nouns[$RANDOM % ${#nouns[@]}]}
    echo "$adj $noun"
}

generate_role() {
    local roles=("VILLAGER" "MAFIA" "SHERIFF" "DOCTOR")
    echo ${roles[$RANDOM % ${#roles[@]}]}
}

generate_career() {
    local careers=("Detective" "Nurse" "Teacher" "Engineer" "Artist" "Chef" "Lawyer" "Merchant" "Soldier")
    echo ${careers[$RANDOM % ${#careers[@]}]}
}

# Check if services are running
check_services() {
    print_message $BLUE "🔍 Checking if services are running..."
    
    # Check Game Service
    if curl -s "$GAME_SERVICE_URL/health" > /dev/null 2>&1; then
        print_message $GREEN "✅ Game Service is running at $GAME_SERVICE_URL"
    else
        print_message $RED "❌ Game Service is not accessible at $GAME_SERVICE_URL"
        print_message $YELLOW "💡 Make sure to start the service with: docker-compose up -d game-service"
        exit 1
    fi
    
    # Check User Service (for getting user IDs)
    if curl -s "$USER_SERVICE_URL/docs.json" > /dev/null 2>&1; then
        print_message $GREEN "✅ User Service is running at $USER_SERVICE_URL"
    else
        print_message $RED "❌ User Service is not accessible at $USER_SERVICE_URL"
        print_message $YELLOW "💡 Make sure the User Management Service is running"
        exit 1
    fi
}

# Get existing users from User Management Service
get_users() {
    print_message $BLUE "👥 Fetching existing users from User Management Service..."
    
    users_response=$(curl -s "$USER_SERVICE_URL/v1/users?limit=50")
    if [ $? -eq 0 ]; then
        # Extract user IDs using grep and sed
        USER_IDS=($(echo "$users_response" | grep -o '"id":"[^"]*"' | sed 's/"id":"//' | sed 's/"//' | head -25))
        
        if [ ${#USER_IDS[@]} -eq 0 ]; then
            print_message $RED "❌ No users found in User Management Service"
            print_message $YELLOW "💡 Please run the user seeding script first: ./scripts/seed_user_management.sh"
            exit 1
        fi
        
        print_message $GREEN "✅ Found ${#USER_IDS[@]} users"
    else
        print_message $RED "❌ Failed to fetch users from User Management Service"
        exit 1
    fi
}

# Create lobbies
create_lobbies() {
    print_message $BLUE "🏛️ Creating $NUM_LOBBIES lobbies..."
    
    for i in $(seq 1 $NUM_LOBBIES); do
        lobby_name=$(generate_lobby_name)
        
        response=$(curl -s -w "%{http_code}" -X POST "$GAME_SERVICE_URL/v1/lobby" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"$lobby_name\"
            }")
        
        http_code="${response: -3}"
        response_body="${response%???}"
        
        if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
            # Try to extract lobby ID from response
            lobby_id=$(echo "$response_body" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ -n "$lobby_id" ]; then
                CREATED_LOBBIES+=("$lobby_id")
                print_message $GREEN "   ✅ Created lobby: $lobby_name - ID: $lobby_id"
            else
                print_message $YELLOW "   ⚠️ Created lobby: $lobby_name (ID extraction failed)"
            fi
        else
            print_message $RED "   ❌ Failed to create lobby $lobby_name: HTTP $http_code"
            if [ -n "$response_body" ]; then
                print_message $RED "      Response: $response_body"
            fi
        fi
    done
}

# Add players to lobbies
add_players_to_lobbies() {
    print_message $BLUE "👥 Adding players to lobbies..."
    
    for lobby_id in "${CREATED_LOBBIES[@]}"; do
        # Add 3-8 players per lobby
        num_players=$((RANDOM % 6 + 3))
        num_players=$(( num_players < ${#USER_IDS[@]} ? num_players : ${#USER_IDS[@]} ))
        
        # Shuffle user IDs and take the first num_players
        shuffled_users=($(printf '%s\n' "${USER_IDS[@]}" | shuf | head -n $num_players))
        
        for j in "${!shuffled_users[@]}"; do
            user_id="${shuffled_users[$j]}"
            
            # Assign roles: first player is MAFIA, second is SHERIFF, third is DOCTOR, rest are VILLAGER
            if [ $j -eq 0 ]; then
                role="MAFIA"
            elif [ $j -eq 1 ]; then
                role="SHERIFF"
            elif [ $j -eq 2 ]; then
                role="DOCTOR"
            else
                role="VILLAGER"
            fi
            
            career=$(generate_career)
            
            response=$(curl -s -w "%{http_code}" -X POST "$GAME_SERVICE_URL/v1/lobby/$lobby_id/players" \
                -H "Content-Type: application/json" \
                -d "{
                    \"userId\": \"$user_id\",
                    \"role\": \"$role\",
                    \"career\": \"$career\"
                }")
            
            http_code="${response: -3}"
            response_body="${response%???}"
            
            if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
                print_message $GREEN "   ✅ Added $role player ($career) to lobby $lobby_id"
            else
                # Show more detailed error for debugging
                print_message $RED "   ❌ Failed to add player $user_id to lobby $lobby_id: HTTP $http_code"
                if [ ! -z "$response_body" ] && [ "$response_body" != "<!DOCTYPE html>" ]; then
                    print_message $YELLOW "      Error: $response_body"
                fi
            fi
        done
    done
}

# Get summary statistics
get_summary() {
    print_message $BLUE "📊 Getting summary statistics..."
    
    lobby_count=${#CREATED_LOBBIES[@]}
    
    print_message $YELLOW "📈 Seeding Summary:"
    print_message $GREEN "   🏛️ Lobbies created: $lobby_count"
    
    # Show sample lobby information
    print_message $YELLOW "🏛️ Sample Lobby Status:"
    for lobby_id in "${CREATED_LOBBIES[@]:0:3}"; do
        lobby_response=$(curl -s "$GAME_SERVICE_URL/v1/lobby/$lobby_id")
        players_response=$(curl -s "$GAME_SERVICE_URL/v1/lobby/$lobby_id/players")
        if [ $? -eq 0 ]; then
            lobby_name=$(echo "$lobby_response" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
            status=$(echo "$lobby_response" | grep -o '"currentStatus":"[^"]*"' | cut -d'"' -f4)
            player_count=$(echo "$players_response" | grep -o '"userId"' | wc -l)
            print_message $GREEN "   $lobby_name: $status | $player_count players"
        fi
    done
}

# Main execution
main() {
    print_message $BLUE "🌱 Starting Game Service database seeding via HTTP API..."
    
    # Initialize array to store created lobby IDs
    CREATED_LOBBIES=()
    
    check_services
    get_users
    create_lobbies
    add_players_to_lobbies
    get_summary
    
    print_message $GREEN "✅ Game Service database seeding completed successfully!"
}

# Run main function
main
