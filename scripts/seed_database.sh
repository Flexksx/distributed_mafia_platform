#!/usr/bin/env bash

# Master Seed Script for Mafia Platform
# This script seeds all service databases via HTTP API calls

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
USER_SERVICE_URL="${USER_SERVICE_URL:-http://localhost:3000}"
GAME_SERVICE_URL="${GAME_SERVICE_URL:-http://localhost:3001}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Helper function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Helper function to print section headers
print_header() {
    local message=$1
    echo
    print_message $PURPLE "═══════════════════════════════════════════════════════════════"
    print_message $PURPLE "  $message"
    print_message $PURPLE "═══════════════════════════════════════════════════════════════"
    echo
}

# Check if services are running
check_services() {
    print_header "SERVICE HEALTH CHECKS"
    
    local all_services_running=true
    
    # Check User Management Service
    print_message $BLUE "🔍 Checking User Management Service..."
    if curl -s "$USER_SERVICE_URL/docs.json" > /dev/null 2>&1; then
        print_message $GREEN "✅ User Management Service is running at $USER_SERVICE_URL"
    else
        print_message $RED "❌ User Management Service is not accessible at $USER_SERVICE_URL"
        all_services_running=false
    fi
    
    # Check Game Service  
    print_message $BLUE "🔍 Checking Game Service..."
    if curl -s "$GAME_SERVICE_URL/health" > /dev/null 2>&1; then
        print_message $GREEN "✅ Game Service is running at $GAME_SERVICE_URL"
    else
        print_message $YELLOW "⚠️ Game Service is not accessible at $GAME_SERVICE_URL"
        print_message $YELLOW "   Game service seeding will be skipped"
    fi
    
    if [ "$all_services_running" = false ]; then
        print_message $RED "❌ Critical services are not running"
        print_message $YELLOW "💡 Start services with: docker-compose up -d"
        exit 1
    fi
}

# Make scripts executable
make_scripts_executable() {
    print_message $BLUE "🔧 Making seed scripts executable..."
    chmod +x "$SCRIPT_DIR/seed_user_management.sh"
    chmod +x "$SCRIPT_DIR/seed_game_service.sh"
    print_message $GREEN "✅ Scripts are now executable"
}

# Seed User Management Service
seed_user_management() {
    print_header "SEEDING USER MANAGEMENT SERVICE"
    
    if [ -f "$SCRIPT_DIR/seed_user_management.sh" ]; then
        export USER_SERVICE_URL
        "$SCRIPT_DIR/seed_user_management.sh"
    else
        print_message $RED "❌ User management seed script not found"
        exit 1
    fi
}

# Seed Game Service
seed_game_service() {
    print_header "SEEDING GAME SERVICE"
    
    # Check if Game Service is accessible
    if curl -s "$GAME_SERVICE_URL/health" > /dev/null 2>&1; then
        if [ -f "$SCRIPT_DIR/seed_game_service.sh" ]; then
            export USER_SERVICE_URL
            export GAME_SERVICE_URL
            "$SCRIPT_DIR/seed_game_service.sh"
        else
            print_message $RED "❌ Game service seed script not found"
        fi
    else
        print_message $YELLOW "⚠️ Skipping Game Service seeding (service not available)"
    fi
}

# Display final summary
display_summary() {
    print_header "SEEDING COMPLETE"
    
    print_message $GREEN "🎉 Database seeding completed successfully!"
    echo
    print_message $BLUE "📋 What was created:"
    print_message $GREEN "   👥 Sample users with profiles"
    print_message $GREEN "   📱 Device registrations" 
    print_message $GREEN "   💰 Currency transactions"
    print_message $GREEN "   🔐 Access event logs"
    
    # Check if Game Service was seeded
    if curl -s "$GAME_SERVICE_URL/health" > /dev/null 2>&1; then
        print_message $GREEN "   🏛️ Game lobbies with players"
    fi
    
    echo
    print_message $BLUE "🌐 Service URLs:"
    print_message $YELLOW "   User Management API: $USER_SERVICE_URL/docs"
    
    if curl -s "$GAME_SERVICE_URL/health" > /dev/null 2>&1; then
        print_message $YELLOW "   Game Service API: $GAME_SERVICE_URL"
    fi
    
    echo
    print_message $BLUE "🧪 Test the APIs:"
    print_message $YELLOW "   curl $USER_SERVICE_URL/v1/users"
    
    if curl -s "$GAME_SERVICE_URL/health" > /dev/null 2>&1; then
        print_message $YELLOW "   curl $GAME_SERVICE_URL/v1/lobby"
    fi
}

# Handle script interruption
cleanup() {
    print_message $YELLOW "🛑 Seeding interrupted by user"
    exit 1
}

trap cleanup SIGINT SIGTERM

# Main execution
main() {
    print_header "MAFIA PLATFORM DATABASE SEEDING"
    print_message $BLUE "🌱 Starting comprehensive database seeding via HTTP APIs..."
    print_message $BLUE "⏱️  This will take approximately 1-2 minutes to complete"
    echo
    
    make_scripts_executable
    check_services
    seed_user_management
    
    # Add a small delay between services
    print_message $BLUE "⏳ Waiting 3 seconds before seeding game service..."
    sleep 3
    
    seed_game_service
    display_summary
}

# Show usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  --user-service-url URL  Set User Management Service URL (default: http://localhost:3000)"
    echo "  --game-service-url URL  Set Game Service URL (default: http://localhost:3001)"
    echo
    echo "Environment Variables:"
    echo "  USER_SERVICE_URL        User Management Service base URL"
    echo "  GAME_SERVICE_URL        Game Service base URL"
    echo
    echo "Examples:"
    echo "  $0                                          # Use default URLs"
    echo "  $0 --user-service-url http://localhost:3000 # Custom user service URL"
    echo "  USER_SERVICE_URL=http://localhost:3000 $0   # Using environment variable"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --user-service-url)
            USER_SERVICE_URL="$2"
            shift 2
            ;;
        --game-service-url)
            GAME_SERVICE_URL="$2"
            shift 2
            ;;
        *)
            print_message $RED "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
main
