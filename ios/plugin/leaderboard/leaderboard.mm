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

#ifdef __IPHONE_26_0

static id gameActivityDelegate = nil;   // GodotGameActivityDelegate*
static id currentActivity = nil;        // GKGameActivity*
static NSMutableDictionary *activityDefinitions = nil;  // NSString* -> GKGameActivityDefinition*

static Dictionary ns_dict_to_godot(NSDictionary *dict) {
    Dictionary result;
    for (NSString *key in dict) {
        id value = dict[key];
        String godot_key = String([key UTF8String]);
        if ([value isKindOfClass:[NSString class]]) {
            result[godot_key] = String([value UTF8String]);
        } else if ([value isKindOfClass:[NSNumber class]]) {
            result[godot_key] = (int64_t)[value longLongValue];
        }
    }
    return result;
}

API_AVAILABLE(ios(26.0))
@interface GodotGameActivityDelegate : NSObject <GKGameActivityListener>
@end

API_AVAILABLE(ios(26.0))
@implementation GodotGameActivityDelegate

- (void)player:(GKPlayer *)player
    wantsToPlayGameActivity:(GKGameActivity *)activity
          completionHandler:(void (^)(BOOL))completionHandler {
    if (!Leaderboard::get_singleton()) {
        completionHandler(NO);
        return;
    }

    String activity_id = String([activity.activityDefinition.identifier UTF8String]);
    String party_code = activity.partyCode ? String([activity.partyCode UTF8String]) : String();
    Dictionary props = ns_dict_to_godot(activity.activityDefinition.defaultProperties ?: @{});

    Leaderboard::get_singleton()->emit_signal("on_activity_wants_to_play", activity_id, party_code, props);
    completionHandler(YES);
}

@end

#endif // __IPHONE_26_0

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
    ADD_SIGNAL(MethodInfo("on_leaderboard_closed"));
    ADD_SIGNAL(MethodInfo("on_activities_loaded", PropertyInfo(Variant::DICTIONARY, "activities")));
    ADD_SIGNAL(MethodInfo("on_activity_wants_to_play", PropertyInfo(Variant::STRING, "activity_id"), PropertyInfo(Variant::STRING, "party_code"), PropertyInfo(Variant::DICTIONARY, "properties")));
    ADD_SIGNAL(MethodInfo("on_activity_started", PropertyInfo(Variant::STRING, "activity_id"), PropertyInfo(Variant::STRING, "party_code")));
    ADD_SIGNAL(MethodInfo("on_activity_error", PropertyInfo(Variant::STRING, "error_code")));

    ClassDB::bind_method("isAuthenticated", &Leaderboard::isAuthenticated);
    ClassDB::bind_method("signIn", &Leaderboard::signIn);
    ClassDB::bind_method("fetchHighScore", &Leaderboard::fetchHighScore);
    ClassDB::bind_method("submitHighScore", &Leaderboard::submitHighScore);
    ClassDB::bind_method("show", &Leaderboard::show);
    ClassDB::bind_method("loadActivities", &Leaderboard::load_activities);
    ClassDB::bind_method("startActivity", &Leaderboard::start_activity);
    ClassDB::bind_method("startActivityWithCode", &Leaderboard::start_activity_with_code);
    ClassDB::bind_method("endActivity", &Leaderboard::end_activity);
    ClassDB::bind_method("pauseActivity", &Leaderboard::pause_activity);
    ClassDB::bind_method("resumeActivity", &Leaderboard::resume_activity);
    ClassDB::bind_method("getActivityPartyCode", &Leaderboard::get_activity_party_code);
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
#ifdef __IPHONE_26_0
                if (@available(iOS 26.0, *)) {
                    if (!gameActivityDelegate) {
                        gameActivityDelegate = [[GodotGameActivityDelegate alloc] init];
                        [[GKLocalPlayer localPlayer] registerListener:(id<GKLocalPlayerListener>)gameActivityDelegate];
                    }
                }
#endif
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
    emit_signal("on_leaderboard_closed");
}


void Leaderboard::load_activities() {
#ifdef __IPHONE_26_0
    if (@available(iOS 26.0, *)) {
        [GKGameActivityDefinition loadDefinitionsWithCompletionHandler:^(NSArray<GKGameActivityDefinition *> *definitions, NSError *error) {
            if (error || !definitions) {
                emit_signal("on_activity_error", "ERROR_ACTIVITY_LOAD_FAILED");
                return;
            }
            if (!activityDefinitions) {
                activityDefinitions = [NSMutableDictionary dictionary];
            }
            Dictionary result;
            for (GKGameActivityDefinition *def in definitions) {
                activityDefinitions[def.identifier] = def;
                result[String([def.identifier UTF8String])] = String([def.title UTF8String]);
            }
            emit_signal("on_activities_loaded", result);
        }];
        return;
    }
#endif
    emit_signal("on_activity_error", "ERROR_ACTIVITY_UNSUPPORTED");
}


void Leaderboard::start_activity(const String &activity_id) {
#ifdef __IPHONE_26_0
    if (@available(iOS 26.0, *)) {
        NSString *ns_id = [NSString stringWithUTF8String:activity_id.utf8().get_data()];
        GKGameActivityDefinition *def = activityDefinitions[ns_id];
        if (!def) {
            emit_signal("on_activity_error", "ERROR_ACTIVITY_NOT_FOUND");
            return;
        }
        NSError *error;
        GKGameActivity *activity = [GKGameActivity startWithDefinition:def error:&error];
        if (error || !activity) {
            emit_signal("on_activity_error", "ERROR_ACTIVITY_START_FAILED");
            return;
        }
        currentActivity = activity;
        String party_code = activity.partyCode ? String([activity.partyCode UTF8String]) : String();
        emit_signal("on_activity_started", activity_id, party_code);
        return;
    }
#endif
    emit_signal("on_activity_error", "ERROR_ACTIVITY_UNSUPPORTED");
}


void Leaderboard::start_activity_with_code(const String &activity_id, const String &party_code) {
#ifdef __IPHONE_26_0
    if (@available(iOS 26.0, *)) {
        NSString *ns_id = [NSString stringWithUTF8String:activity_id.utf8().get_data()];
        NSString *ns_code = [NSString stringWithUTF8String:party_code.utf8().get_data()];
        GKGameActivityDefinition *def = activityDefinitions[ns_id];
        if (!def) {
            emit_signal("on_activity_error", "ERROR_ACTIVITY_NOT_FOUND");
            return;
        }
        NSError *error;
        GKGameActivity *activity = [GKGameActivity startWithDefinition:def partyCode:ns_code error:&error];
        if (error || !activity) {
            emit_signal("on_activity_error", "ERROR_ACTIVITY_START_FAILED");
            return;
        }
        currentActivity = activity;
        emit_signal("on_activity_started", activity_id, party_code);
        return;
    }
#endif
    emit_signal("on_activity_error", "ERROR_ACTIVITY_UNSUPPORTED");
}


void Leaderboard::end_activity() {
#ifdef __IPHONE_26_0
    if (@available(iOS 26.0, *)) {
        if (currentActivity) {
            [(GKGameActivity *)currentActivity end];
            currentActivity = nil;
        }
        return;
    }
#endif
}


void Leaderboard::pause_activity() {
#ifdef __IPHONE_26_0
    if (@available(iOS 26.0, *)) {
        if (currentActivity) {
            [(GKGameActivity *)currentActivity pause];
        }
        return;
    }
#endif
}


void Leaderboard::resume_activity() {
#ifdef __IPHONE_26_0
    if (@available(iOS 26.0, *)) {
        if (currentActivity) {
            [(GKGameActivity *)currentActivity start];
        }
        return;
    }
#endif
}


String Leaderboard::get_activity_party_code() {
#ifdef __IPHONE_26_0
    if (@available(iOS 26.0, *)) {
        if (currentActivity) {
            NSString *code = [(GKGameActivity *)currentActivity partyCode];
            if (code) {
                return String([code UTF8String]);
            }
        }
    }
#endif
    return String();
}
