# Expand existing pitch movement around its own median, without changing duration.
form Emote prosody
    sentence Source
    sentence Target
    real Spread 1.15
    real Limit 0.75
endform

sound = Read from file: source$
manipulation = To Manipulation: 0.01, 60, 400
tier = Extract pitch tier
count = Get number of points
if count < 5
    writeInfoLine: "unchanged"
else
    times# = zero#(count)
    pitches# = zero#(count)
    for i from 1 to count
        times#[i] = Get time from index: i
        hz = Get value at index: i
        pitches#[i] = ln(hz) / ln(2)
    endfor
    center = quantile(pitches#, 0.5)
    selectObject: sound
    duration = Get total duration
    selectObject: tier
    Remove points between: 0, duration
    for i from 1 to count
        shift = min(limit, max(-limit, (pitches#[i] - center) * 12 * (spread - 1)))
        Add point: times#[i], 2 ^ (pitches#[i] + shift / 12)
    endfor
    selectObject: tier, manipulation
    Replace pitch tier
    selectObject: manipulation
    Get resynthesis (overlap-add)
    peak = Get absolute extremum: 0, 0, "None"
    if peak > 0.98
        Scale peak: 0.98
    endif
    Save as WAV file: target$
endif
