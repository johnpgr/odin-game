package main

import "core:fmt"
import "game"

WIDTH :: 640
HEIGHT :: 480

main :: proc() {
    g := game.Game{}
    defer game.deinit(&g)
    
    if !game.init(&g, WIDTH, HEIGHT) {
        fmt.println("Failed to initialize game")
        return
    }
    
    game.run(&g)
}
