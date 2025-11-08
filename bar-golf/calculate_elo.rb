#!/usr/bin/env ruby

require_relative 'models'

# Setup schema to ensure elo_rating column exists
setup_schema

# Recalculate all ELO ratings
Player.recalculate_all_elo_ratings
