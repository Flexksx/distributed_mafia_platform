#!/usr/bin/env bash

# Seed User Management Service Database via HTTP API
# This script creates sample data by calling the REST API endpoints

set -e

# Configuration
USER_SERVICE_URL="${USER_SERVICE_URL:-http://localhost:3000}"
NUM_USERS=10

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
generate_email() {
    local names=("alice" "bob" "charlie" "diana" "eve" "frank" "grace" "henry" "iris" "jack" "kate" "liam" "maya" "noah" "olivia")
    local domains=("example.com" "test.org" "demo.net" "sample.io" "mock.dev")
    local name=${names[$RANDOM % ${#names[@]}]}
    local domain=${domains[$RANDOM % ${#domains[@]}]}
    echo "${name}${RANDOM}@${domain}"
}

generate_username() {
    local adjectives=("cool" "swift" "brave" "smart" "quick" "wise" "bold" "calm" "sharp" "bright")
    local nouns=("wolf" "eagle" "tiger" "fox" "bear" "lion" "hawk" "shark" "raven" "cobra")
    local adj=${adjectives[$RANDOM % ${#adjectives[@]}]}
    local noun=${nouns[$RANDOM % ${#nouns[@]}]}
    echo "${adj}_${noun}_${RANDOM}"
}

generate_fingerprint() {
    echo "fp_$(openssl rand -hex 16)"
}

generate_platform() {
    local platforms=("WEB" "ANDROID" "IOS" "DESKTOP")
    echo ${platforms[$RANDOM % ${#platforms[@]}]}
}

generate_ip() {
    echo "$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))"
}

generate_country() {
    local countries=("US" "CA" "GB" "DE" "FR" "JP" "AU" "BR" "IN" "MX")
    echo ${countries[$RANDOM % ${#countries[@]}]}
}

generate_transaction_reason() {
    local reasons=("DAILY_BONUS" "GAME_REWARD" "PURCHASE" "GIFT" "QUEST_COMPLETION" "LOGIN_BONUS")
    echo ${reasons[$RANDOM % ${#reasons[@]}]}
}

# Check if service is running
check_service() {
    print_message $BLUE "🔍 Checking if User Management Service is running..."
    if curl -s "$USER_SERVICE_URL/docs.json" > /dev/null; then
        print_message $GREEN "✅ Service is running at $USER_SERVICE_URL"
    else
        print_message $RED "❌ Service is not accessible at $USER_SERVICE_URL"
        print_message $YELLOW "💡 Make sure to start the service with: docker-compose up -d user-management-service"
        exit 1
    fi
}

# Create users
create_users() {
    print_message $BLUE "👥 Creating $NUM_USERS users..."
    
    for i in $(seq 1 $NUM_USERS); do
        email=$(generate_email)
        username=$(generate_username)
        password="password123"
        
        response=$(curl -s -w "%{http_code}" -X POST "$USER_SERVICE_URL/v1/users" \
            -H "Content-Type: application/json" \
            -d "{
                \"email\": \"$email\",
                \"username\": \"$username\",
                \"password\": \"$password\"
            }")
        
        http_code="${response: -3}"
        response_body="${response%???}"
        
        if [ "$http_code" = "201" ]; then
            user_id=$(echo "$response_body" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
            CREATED_USERS+=("$user_id")
            print_message $GREEN "   ✅ Created user: $username ($email) - ID: $user_id"
        else
            print_message $RED "   ❌ Failed to create user $username: HTTP $http_code"
        fi
    done
}

# Create devices for users
create_devices() {
    print_message $BLUE "📱 Creating devices for users..."
    
    for user_id in "${CREATED_USERS[@]}"; do
        # Create 1-3 devices per user
        num_devices=$((RANDOM % 3 + 1))
        
        for j in $(seq 1 $num_devices); do
            fingerprint=$(generate_fingerprint)
            platform=$(generate_platform)
            
            response=$(curl -s -w "%{http_code}" -X POST "$USER_SERVICE_URL/v1/users/$user_id/devices" \
                -H "Content-Type: application/json" \
                -d "{
                    \"device\": {
                        \"fingerprint\": \"$fingerprint\",
                        \"platform\": \"$platform\"
                    }
                }")
            
            http_code="${response: -3}"
            
            if [ "$http_code" = "201" ]; then
                print_message $GREEN "   ✅ Created $platform device for user $user_id"
            else
                print_message $RED "   ❌ Failed to create device for user $user_id: HTTP $http_code"
            fi
        done
    done
}

# Create transactions for users
create_transactions() {
    print_message $BLUE "💰 Creating currency transactions..."
    
    for user_id in "${CREATED_USERS[@]}"; do
        # Create 3-8 transactions per user
        num_transactions=$((RANDOM % 6 + 3))
        
        for j in $(seq 1 $num_transactions); do
            # 70% chance for ADD, 30% for SUBTRACT
            if [ $((RANDOM % 10)) -lt 7 ]; then
                transaction_type="ADD"
                amount=$((RANDOM % 491 + 10))  # 10-500
            else
                transaction_type="SUBTRACT"
                amount=$((RANDOM % 96 + 5))    # 5-100
            fi
            
            reason=$(generate_transaction_reason)
            
            response=$(curl -s -w "%{http_code}" -X POST "$USER_SERVICE_URL/v1/users/$user_id/transactions" \
                -H "Content-Type: application/json" \
                -d "{
                    \"amount\": $amount,
                    \"type\": \"$transaction_type\",
                    \"reason\": \"$reason\"
                }")
            
            http_code="${response: -3}"
            
            if [ "$http_code" = "201" ]; then
                print_message $GREEN "   ✅ Created $transaction_type transaction of $amount for user $user_id"
            else
                print_message $RED "   ❌ Failed to create transaction for user $user_id: HTTP $http_code"
            fi
        done
    done
}

# Create access events for users
create_access_events() {
    print_message $BLUE "🔐 Creating access events..."
    
    for user_id in "${CREATED_USERS[@]}"; do
        # Create 5-15 access events per user
        num_events=$((RANDOM % 11 + 5))
        
        for j in $(seq 1 $num_events); do
            ip=$(generate_ip)
            country=$(generate_country)
            
            response=$(curl -s -w "%{http_code}" -X POST "$USER_SERVICE_URL/v1/users/$user_id/access-events" \
                -H "Content-Type: application/json" \
                -d "{
                    \"ip\": \"$ip\",
                    \"country\": \"$country\"
                }")
            
            http_code="${response: -3}"
            
            if [ "$http_code" = "201" ]; then
                print_message $GREEN "   ✅ Created access event from $country for user $user_id"
            else
                print_message $RED "   ❌ Failed to create access event for user $user_id: HTTP $http_code"
            fi
        done
    done
}

# Get summary statistics
get_summary() {
    print_message $BLUE "📊 Getting summary statistics..."
    
    # Get user count
    users_response=$(curl -s "$USER_SERVICE_URL/v1/users")
    user_count=$(echo "$users_response" | grep -o '"id"' | wc -l)
    
    print_message $YELLOW "📈 Seeding Summary:"
    print_message $GREEN "   👥 Users created: $user_count"
    
    # Show sample user balances
    print_message $YELLOW "💰 Sample User Balances:"
    for user_id in "${CREATED_USERS[@]:0:5}"; do
        balance_response=$(curl -s "$USER_SERVICE_URL/v1/users/$user_id/balance")
        if [ $? -eq 0 ]; then
            balance=$(echo "$balance_response" | grep -o '"balance":[0-9]*' | cut -d':' -f2)
            total_transactions=$(echo "$balance_response" | grep -o '"totalTransactions":[0-9]*' | cut -d':' -f2)
            print_message $GREEN "   User $user_id: $balance credits ($total_transactions transactions)"
        fi
    done
}

# Main execution
main() {
    print_message $BLUE "🌱 Starting User Management Service database seeding via HTTP API..."
    
    # Initialize array to store created user IDs
    CREATED_USERS=()
    
    check_service
    create_users
    create_devices
    create_transactions
    create_access_events
    get_summary
    
    print_message $GREEN "✅ User Management Service database seeding completed successfully!"
}

# Run main function
main
