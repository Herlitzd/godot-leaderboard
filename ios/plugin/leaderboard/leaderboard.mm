#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

#ifdef VERSION_4_0
#include "core/object/class_db.h"
#else
#include "core/class_db.h"
#endif

#include "leaderboard.h"
#import <GameKit/GameKit.h>
#import "game_center_delegate.h"

Leaderboard *Leaderboard::instance = NULL;
GodotGameCenterDelegate *gameCenterDelegate = nil;

Leaderboard::Leaderboard() {
    instance = this;
    gameCenterDelegate = [[GodotGameCenterDelegate alloc] init];
    NSLog(@"initialize leaderboard");
}

Leaderboard::~Leaderboard() {
    if (instance == this) {
        instance = NULL;
    }
    if (gameCenterDelegate) {
        gameCenterDelegate = nil;
    }
    NSLog(@"deinitialize leaderboard");
}

Leaderboard *Leaderboard::get_singleton() {
    return instance;
};

void Leaderboard::_bind_methods() {
    ADD_SIGNAL(MethodInfo("on_leaderboard_error", PropertyInfo(Variant::STRING, "error_code")));
    ADD_SIGNAL(MethodInfo("on_leaderboard_event", PropertyInfo(Variant::STRING, "event_code")));
    ADD_SIGNAL(MethodInfo("on_authenticated", PropertyInfo(Variant::BOOL, "is_authenticated")));
    ADD_SIGNAL(MethodInfo("on_high_score_fetched", PropertyInfo(Variant::INT, "highscore")));

    ClassDB::bind_method("isAuthenticated", &Leaderboard::isAuthenticated);
    ClassDB::bind_method("signIn", &Leaderboard::signIn);
    ClassDB::bind_method("fetchHighScore", &Leaderboard::fetchHighScore);
    ClassDB::bind_method("submitHighScore", &Leaderboard::submitHighScore);
    ClassDB::bind_method("show", &Leaderboard::show);
}

bool Leaderboard::isAuthenticated() {
    GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
    return localPlayer.isAuthenticated;
}

// Hàm bổ trợ lấy rootViewController an toàn trên iOS 14+
UIViewController* get_safe_root_controller() {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                window = scene.windows.firstObject;
                break;
            }
        }
    }
    if (!window) {
        window = [UIApplication sharedApplication].keyWindow;
    }
    if (!window) {
        window = [[UIApplication sharedApplication] delegate].window;
    }
    return window.rootViewController;
}

void Leaderboard::signIn() {
    if ((NSClassFromString(@"GKLocalPlayer")) == nil) {
        emit_signal("on_leaderboard_error", "ERROR_INIT_NO_CLASS");
        return;
    }

    GKLocalPlayer *player = [GKLocalPlayer localPlayer];
    if (![player respondsToSelector:@selector(authenticateHandler)]) {
        emit_signal("on_leaderboard_error", "ERROR_INIT_NO_SELECTOR");
        return;
    }

    // Sử dụng hàm lấy root mới an toàn hơn
    UIViewController *root_controller = get_safe_root_controller();
    
    if (!root_controller) {
        emit_signal("on_leaderboard_error", "ERROR_INIT_NO_ROOT");
        return;
    }

    _weakify(root_controller);
    _weakify(player);
    player.authenticateHandler = (^(UIViewController *controller, NSError *error) {
        _strongify(root_controller);
        _strongify(player);

        if (controller) {
            [root_controller presentViewController:controller animated:YES completion:nil];
        } else {
            if (player.isAuthenticated) {
                emit_signal("on_authenticated", true);
            } else {
                emit_signal("on_authenticated", false);
            }
        }
    });
}

void Leaderboard::fetchHighScore(const String &leaderboard_id) {
    // Lưu ý: Đoạn này tạm giữ nguyên theo code cũ của bạn để chạy tạm, 
    // nhưng khuyến khích cập nhật sang GKLeaderboard loadEntries nếu chạy iOS 14+ hoàn toàn.
    GKLeaderboard *leaderboard = [[GKLeaderboard alloc] init];
    leaderboard.identifier = [[NSString alloc] initWithUTF8String:leaderboard_id.utf8().get_data()];
    leaderboard.playerScope = GKLeaderboardPlayerScopeGlobal;
    leaderboard.timeScope = GKLeaderboardTimeScopeAllTime;
    
    [leaderboard loadScoresWithCompletionHandler:^(NSArray<GKScore *> *scores, NSError *error) {
        if (!error) {
            if (leaderboard.localPlayerScore) {
                emit_signal("on_high_score_fetched", leaderboard.localPlayerScore.value);
            } else {
                emit_signal("on_leaderboard_error", "PLAYER_NO_SCORE");
            }
        } else {
            emit_signal("on_leaderboard_error", "ERROR_FETCH_HIGHSCORE_FAILED");
        }
    }];
}

void Leaderboard::submitHighScore(const String &leaderboard_id, const int &score) {
    NSString *leaderboard_ns_id = [NSString stringWithUTF8String:leaderboard_id.utf8().get_data()];
    
    // Sử dụng API mới từ iOS 14+ để submit điểm thẳng vào Leaderboard ID
    if (@available(iOS 14.0, *)) {
        [GKLeaderboard submitScore:score
                        context:0
                         player:[GKLocalPlayer localPlayer]
         leaderboardIDs:@[leaderboard_ns_id]
              completionHandler:^(NSError * _Nullable error) {
            if (error == nil) {
                emit_signal("on_leaderboard_event", "EVENT_SUBMIT_SCORE_OK");
            } else {
                emit_signal("on_leaderboard_event", "EVENT_SUBMIT_SCORE_ERROR");
            }
        }];
    } else {
        // Fallback cho iOS cũ (Dưới iOS 14)
        GKScore *reporter = [[GKScore alloc] initWithLeaderboardIdentifier:leaderboard_ns_id];
        reporter.value = score;

        [GKScore reportScores:@[ reporter ] withCompletionHandler:^(NSError *error) {
            if (error == nil) {
                emit_signal("on_leaderboard_event", "EVENT_SUBMIT_SCORE_OK");
            } else {
                emit_signal("on_leaderboard_event", "EVENT_SUBMIT_SCORE_ERROR");
            }
        }];
    }
}

void Leaderboard::show(const String &leaderboard_id) {
    if (!NSProtocolFromString(@"GKGameCenterControllerDelegate")) {
        emit_signal("on_leaderboard_error", "ERROR_NO_CENTER_CONTROLLER");
        return;
    }

    GKGameCenterViewController *controller = [[GKGameCenterViewController alloc] init];
    if (!controller) {
        emit_signal("on_leaderboard_error", "ERROR_CANT_SHOW_LEADERBOARD");
        return;
    }

    controller.leaderboardIdentifier = [NSString stringWithUTF8String:leaderboard_id.ascii().get_data()];
    controller.leaderboardTimeScope = GKLeaderboardTimeScopeAllTime;

    // Sử dụng hàm lấy root mới an toàn hơn
    UIViewController *root_controller = get_safe_root_controller();
    
    if (!root_controller) {
        emit_signal("on_leaderboard_error", "ERROR_CANT_SHOW_LEADERBOARD");
        return;
    }
    
    controller.gameCenterDelegate = gameCenterDelegate;
    controller.viewState = GKGameCenterViewControllerStateLeaderboards;

    [root_controller presentViewController:controller animated:YES completion:nil];
}

void Leaderboard::game_center_closed() {
    // Tùy biến xử lý khi đóng cửa sổ
}
