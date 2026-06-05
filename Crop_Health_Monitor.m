function CropHealthMonitor()
% =========================================================================
% CropHealthMonitor - Drone / Sentinel-2 Crop Health & NDVI Tool


 %% ----------------------------------------------------------------
 %% Shared state  (accessible to all nested callbacks)
    S.nir       = [];
    S.red       = [];
    S.green     = [];       % optional green band (B03) for EVI / GNDVI
    S.ndvi      = [];
    S.cls       = [];
    S.thresh    = 0.30;
    S.scene     = 'Unknown';

    
    %% Colour palette
    BG  = [0.10, 0.10, 0.12];
    PAN = [0.15, 0.15, 0.18];
    FG  = [0.88, 0.88, 0.88];
    BTN = [0.20, 0.20, 0.25];

    % 6-class health colourmap  (index 0-5)
    %   0 = background/NaN   1 = Water   2 = Stressed
    %   3 = Moderate         4 = Healthy 5 = Very Healthy
    HCMAP = [0.08, 0.08, 0.10;   % 0  Background (dark)
             0.10, 0.28, 0.85;   % 1  Water / Non-veg (blue)
             0.92, 0.18, 0.10;   % 2  Stressed (red)
             0.98, 0.80, 0.10;   % 3  Moderate (yellow)
             0.12, 0.88, 0.22;   % 4  Healthy (bright green)
             0.04, 0.40, 0.10];  % 5  Very Healthy (dark green)

    %% Main figure  (adaptive to screen size)
    scr  = get(0,'ScreenSize');
    figW = min(1620, scr(3) - 20);
    figH = min(920,  scr(4) - 60);
    fig = uifigure( ...
        'Name',     'Crop Health Monitor  |  NDVI Estimator', ...
        'Position', [10, 30, figW, figH], ...
        'Color',    BG);

    %% Title strip
    uilabel(fig, ...
        'Text', '  Crop Health Monitor  ——  NDVI Estimator |   5-Zone Analysis  |  Ocean / Road / Desert Support And Automatic Scene Classification', ...
        'Position', [0, figH-32, figW, 32], 'FontSize',13, 'FontWeight','bold', ...
        'FontColor', [0.92,0.85,0.25], 'BackgroundColor', [0.06,0.06,0.08]);

    %% Status bar
    statusLbl = uilabel(fig, ...
        'Text', '  Ready — Browse Sentinel-2 bands or choose a sample-data scene.', ...
        'Position', [0, figH-54, figW, 22], 'FontSize',9.5, ...
        'FontColor', [0.38,0.90,0.38], 'BackgroundColor', [0.06,0.06,0.08]);

    %% ----------------------------------------------------------------
    %% Three main image panels
    iW=480; iH=figH-390; gap=10; iY=308;
    x1=6;  x2=x1+iW+gap;  x3=x2+iW+gap;

    [axRGB,  btnRGB]  = makeImgPanel(x1, '(Step 1) RGB Composite — NIR=R  Red=G  Blue=B', ...
                                     'Show RGB',        @(~,~)showRGB(),       [0.15,0.28,0.55]);
    [axNDVI, btnNDVI] = makeImgPanel(x2, '(Step 2) NDVI = (NIR − Red) / (NIR + Red)', ...
                                     'Calculate NDVI',  @(~,~)calcNDVI(),      [0.12,0.42,0.18]);

    % --- Classification panel (custom: map + embedded histogram side-by-side) ---
    clsP = uipanel(fig,'Position',[x3, iY, iW, iH], ...
        'BackgroundColor',[0.06,0.06,0.08], ...
        'ForegroundColor',[0.40,0.40,0.46]);
    uilabel(clsP,'Text','(Step 3) Classification  (6 classes  |  drag slider)', ...
        'Position',[5,iH-26,iW-160,22], ...
        'FontSize',8.8,'FontColor',[0.52,0.52,0.58], ...
        'BackgroundColor',[0.06,0.06,0.08]);
    btnCLS = uibutton(clsP,'push','Text','Reclassify', ...
        'Position',[iW-152,iH-28,148,24], ...
        'FontSize',9,'FontWeight','bold', ...
        'BackgroundColor',[0.42,0.16,0.42],'FontColor',FG, ...
        'ButtonPushedFcn',@(~,~)classify());
    % Map occupies left ~65% of panel; histogram right ~33%
    clsMapW = round(iW*0.63);
    histW   = iW - clsMapW - 8;
    axCLS = uiaxes(clsP,'Position',[2, 2, clsMapW, iH-36], ...
        'Color',[0.04,0.04,0.06], ...
        'XColor',[0.28,0.28,0.32],'YColor',[0.28,0.28,0.32], ...
        'XTickLabel',{},'YTickLabel',{});
    axClsHist = uiaxes(clsP,'Position',[clsMapW+4, 2, histW, iH-36], ...
        'Color',[0.04,0.04,0.06], ...
        'XColor',[0.50,0.50,0.55],'YColor',[0.50,0.50,0.55], ...
        'FontSize',7.5);
    title(axClsHist, 'Zone Coverage', 'Color',[0.65,0.65,0.70],'FontSize',8);
    ylabel(axClsHist,'%','Color',[0.60,0.60,0.65]);
    axClsHist.XTick = 1:5;
    axClsHist.XTickLabel = {'Water','Stress','Mod','Hlth','V.Hlth'};
    axClsHist.XTickLabelRotation = 40;

    %% Scene-type badge (above right panel)
    sceneLbl = uilabel(fig, 'Text','  Scene: Unknown', ...
        'Position',[x3, iY+iH+2, 280, 18], ...
        'FontSize',9, 'FontColor',[0.70,0.95,0.70], ...
        'BackgroundColor',[0.08,0.18,0.08]);

    %% ----------------------------------------------------------------
    %% BOTTOM-LEFT:  Input + Options  (w=480)
    bpX=x1; bpW=480; bpH=300;
    browseP = uipanel(fig,'Title','  Input Images  &  Processing Options', ...
        'Position',[bpX,4,bpW,bpH], ...
        'BackgroundColor',PAN,'ForegroundColor',FG,'FontSize',11,'FontWeight','bold');

    % NIR row
    uilabel(browseP,'Text','NIR Band:','Position',[8,246,74,22],'FontColor',FG,'BackgroundColor',PAN);
    nirLbl = uilabel(browseP,'Text','No file selected', ...
        'Position',[88,246,292,22],'FontColor',[0.50,0.50,0.55],'BackgroundColor',PAN);
    uibutton(browseP,'push','Text','Browse','Position',[386,244,82,26], ...
        'BackgroundColor',BTN,'FontColor',FG,'ButtonPushedFcn',@(~,~)browseNIR());

    % Red row
    uilabel(browseP,'Text','Red Band:','Position',[8,212,74,22],'FontColor',FG,'BackgroundColor',PAN);
    redLbl = uilabel(browseP,'Text','No file selected', ...
        'Position',[88,212,292,22],'FontColor',[0.50,0.50,0.55],'BackgroundColor',PAN);
    uibutton(browseP,'push','Text','Browse','Position',[386,210,82,26], ...
        'BackgroundColor',BTN,'FontColor',FG,'ButtonPushedFcn',@(~,~)browseRed());

    % Green (optional)
    uilabel(browseP,'Text','Green (opt):','Position',[8,178,84,22], ...
        'FontColor',[0.60,0.60,0.65],'BackgroundColor',PAN);
    greenLbl = uilabel(browseP,'Text','Optional — enables EVI & GNDVI', ...
        'Position',[96,178,284,22],'FontColor',[0.38,0.38,0.44],'BackgroundColor',PAN);
    uibutton(browseP,'push','Text','Browse','Position',[386,176,82,26], ...
        'BackgroundColor',[0.15,0.15,0.20],'FontColor',[0.55,0.55,0.60], ...
        'ButtonPushedFcn',@(~,~)browseGreen());

    % Divider
    uilabel(browseP,'Text','───────────── or use a built-in sample scene ─────────────', ...
        'Position',[4,150,472,18],'FontColor',[0.35,0.35,0.40], ...
        'BackgroundColor',PAN,'HorizontalAlignment','center');

    % Sample data buttons (2 x 2 grid)
    sampleDefs = { ...
        'Agricultural Field (crops)',  [0.10,0.36,0.10], 'field'; ...
        'Ocean / Water Body',          [0.08,0.18,0.58], 'ocean'; ...
        'Road / Urban Scene',          [0.38,0.28,0.08], 'road';  ...
        'Desert / Bare Soil',          [0.46,0.32,0.10], 'desert' };
    for si=1:4
        col=mod(si-1,2); row=floor((si-1)/2);
        xb=6+col*235; yb=118-row*36;
        uibutton(browseP,'push','Text',sampleDefs{si,1}, ...
            'Position',[xb,yb,230,28], ...
            'BackgroundColor',sampleDefs{si,2},'FontColor','white', ...
            'FontSize',9.5,'FontWeight','bold', ...
            'ButtonPushedFcn',@(~,~)useSampleData(sampleDefs{si,3}));
    end

    % Classify / Filter dropdowns
    uilabel(browseP,'Text','Classify:','Position',[8,30,66,22],'FontColor',FG,'BackgroundColor',PAN);
    classDD = uidropdown(browseP, ...
        'Items',{'Threshold','K-Means (4)','K-Means (6)','Otsu (4)','Otsu + Water'}, ...
        'Value','Threshold','Position',[78,30,160,24], ...
        'BackgroundColor',[0.18,0.18,0.22],'FontColor',FG, ...
        'ValueChangedFcn',@(~,~)onMethodChange());

    uilabel(browseP,'Text','Filter:','Position',[248,30,50,22],'FontColor',FG,'BackgroundColor',PAN);
    filterDD = uidropdown(browseP, ...
        'Items',{'None','Gaussian','Median','Wiener','Bilateral-like'}, ...
        'Value','Gaussian','Position',[300,30,168,24], ...
        'BackgroundColor',[0.18,0.18,0.22],'FontColor',FG);

    %% ----------------------------------------------------------------
    %% BOTTOM-MIDDLE:  Statistics + Analysis buttons  (w=400)
    statsP = uipanel(fig,'Title','  NDVI Statistics  &  Analysis Tools', ...
        'Position',[bpX+bpW+8,4,400,300], ...
        'BackgroundColor',PAN,'ForegroundColor',FG,'FontSize',11,'FontWeight','bold');

    % Four stat readouts
    uilabel(statsP,'Text','Maximum:','Position',[8,254,90,22],'FontSize',10.5,'FontColor',FG,'BackgroundColor',PAN);
    maxLbl  = uilabel(statsP,'Text','---','Position',[104,254,288,22],'FontSize',11,'FontWeight','bold','FontColor',[0.95,0.28,0.18],'BackgroundColor',PAN);

    uilabel(statsP,'Text','Minimum:','Position',[8,224,90,22],'FontSize',10.5,'FontColor',FG,'BackgroundColor',PAN);
    minLbl  = uilabel(statsP,'Text','---','Position',[104,224,288,22],'FontSize',11,'FontWeight','bold','FontColor',[0.25,0.52,0.95],'BackgroundColor',PAN);

    uilabel(statsP,'Text','Mean:','Position',[8,194,90,22],'FontSize',10.5,'FontColor',FG,'BackgroundColor',PAN);
    meanLbl = uilabel(statsP,'Text','---','Position',[104,194,288,22],'FontSize',11,'FontWeight','bold','FontColor',[0.28,0.88,0.38],'BackgroundColor',PAN);

    uilabel(statsP,'Text','Std Dev:','Position',[8,164,90,22],'FontSize',10.5,'FontColor',FG,'BackgroundColor',PAN);
    stdLbl  = uilabel(statsP,'Text','---','Position',[104,164,288,22],'FontSize',11,'FontWeight','bold','FontColor',[0.90,0.65,0.20],'BackgroundColor',PAN);

    % Six analysis buttons  (3 rows × 2 cols)
    abDefs = { ...
        'Raw vs Filtered',           [0.15,0.30,0.55], @(~,~)showRawVsFiltered(); ...
        'Compare Indices',           [0.30,0.15,0.55], @(~,~)compareIndices();    ...
        'NDVI Histogram + CDF',      [0.10,0.35,0.38], @(~,~)showHistogram();     ...
        'Stress Hotspots',           [0.55,0.10,0.10], @(~,~)showStressHotspots(); ...
        'Compare Methods + CM',      [0.42,0.22,0.06], @(~,~)compareAllMethods(); ...
        'Export  (CSV + PNG)',       [0.50,0.10,0.10], @(~,~)exportResults();     ...
    };
    bW=186; bH=26; bGap=4;
    for bi=1:6
        col=mod(bi-1,2); row=floor((bi-1)/2);
        xb=6 + col*(bW+bGap);
        yb=6 + (2-row)*(bH+bGap+2);
        uibutton(statsP,'push','Text',abDefs{bi,1}, ...
            'Position',[xb,yb,bW,bH], ...
            'BackgroundColor',abDefs{bi,2},'FontColor','white', ...
            'FontSize',9,'FontWeight','bold', ...
            'ButtonPushedFcn',abDefs{bi,3});
    end

    %% ----------------------------------------------------------------
    %% BOTTOM-RIGHT:  Threshold slider + Zone statistics text area
    thrPx = bpX+bpW+8+400+8;
    thrPw = figW - thrPx - 4;
    thrP = uipanel(fig,'Title','  Threshold Control  &  Zone Statistics', ...
        'Position',[thrPx, 4, thrPw, 300], ...
        'BackgroundColor',PAN,'ForegroundColor',FG,'FontSize',11,'FontWeight','bold');

    % Current T readout  (compact layout so nothing overflows)
    uilabel(thrP,'Text','T =','Position',[8,258,30,22], ...
        'FontSize',11,'FontColor',FG,'BackgroundColor',PAN);
    thrValLbl = uilabel(thrP,'Text',sprintf('%.2f',S.thresh), ...
        'Position',[40,258,52,22],'FontSize',12,'FontWeight','bold', ...
        'FontColor',[0.22,0.92,0.32],'BackgroundColor',PAN);

    % Dynamic boundary readout — all fit within thrPw
    uilabel(thrP,'Text','Stressed <','Position',[100,258,76,22], ...
        'FontSize',9.5,'FontColor',[0.92,0.30,0.30],'BackgroundColor',PAN);
    stressBndLbl = uilabel(thrP,'Text',sprintf('%.2f',S.thresh/2), ...
        'Position',[178,258,46,22],'FontSize',9.5,'FontWeight','bold', ...
        'FontColor',[0.95,0.50,0.20],'BackgroundColor',PAN);
    uilabel(thrP,'Text','Moderate <','Position',[228,258,78,22], ...
        'FontSize',9.5,'FontColor',[0.98,0.85,0.15],'BackgroundColor',PAN);
    modBndLbl = uilabel(thrP,'Text',sprintf('%.2f',S.thresh), ...
        'Position',[308,258,46,22],'FontSize',9.5,'FontWeight','bold', ...
        'FontColor',[0.98,0.85,0.15],'BackgroundColor',PAN);
    uilabel(thrP,'Text','Healthy <','Position',[358,258,70,22], ...
        'FontSize',9.5,'FontColor',[0.20,0.88,0.30],'BackgroundColor',PAN);
    hlthBndLbl = uilabel(thrP,'Text',sprintf('%.2f',S.thresh+0.20), ...
        'Position',[430,258,48,22],'FontSize',9.5,'FontWeight','bold', ...
        'FontColor',[0.20,0.88,0.30],'BackgroundColor',PAN);
    uilabel(thrP,'Text','V.Healthy ≥','Position',[482,258,82,22], ...
        'FontSize',9.5,'FontColor',[0.04,0.65,0.18],'BackgroundColor',PAN);
    vhlthBndLbl = uilabel(thrP,'Text',sprintf('%.2f',S.thresh+0.20), ...
        'Position',[566,258,52,22],'FontSize',9.5,'FontWeight','bold', ...
        'FontColor',[0.04,0.65,0.18],'BackgroundColor',PAN);

    % Slider
    uislider(thrP,'Limits',[0.05,0.80],'Value',S.thresh, ...
        'Position',[10,236,thrPw-22,3], ...
        'MajorTicks',[0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8], ...
        'FontColor',FG, 'ValueChangedFcn',@(sl,~)onThreshChange(sl));

    % Zone colour legend
    legItems = {'■ Water: NDVI<0','■ Stressed: 0→T/2','■ Moderate: T/2→T', ...
                '■ Healthy: T→T+.2','■ V.Healthy: ≥T+.2'};
    legClrs  = {[0.2,0.4,1],[1,0.3,0.2],[1,0.85,0.1],[0.2,1,0.3],[0.1,0.5,0.1]};
    legW = floor((thrPw-8)/5);
    for li=1:5
        xx=4+(li-1)*legW;
        uilabel(thrP,'Text',legItems{li},'Position',[xx,214,legW,18], ...
            'FontSize',7.5,'FontColor',legClrs{li},'BackgroundColor',PAN);
    end

    % Scrollable stats text area
    statsTA = uitextarea(thrP,'Position',[6,6,thrPw-12,204], ...
        'Value',{'  Run NDVI pipeline to see zone statistics …'}, ...
        'BackgroundColor',[0.06,0.07,0.09],'FontColor',[0.72,0.94,0.72], ...
        'FontSize',10,'Editable','off');

    %% ================================================================
    %%  NESTED CALLBACKS
    %% ================================================================

    function browseNIR()
        [f,p] = uigetfile( ...
            {'*.tif;*.tiff;*.jp2;*.png;*.jpg;*.img','Image files'}, ...
            'Select NIR Band (e.g. B08)');
        if isequal(f,0), return; end
        setStatus('Loading NIR band …','info'); drawnow;
        S.nir = loadBand(fullfile(p,f));
        nirLbl.Text = f;
        setStatus(['NIR loaded: ' f '   |   Now browse the Red band.'],'ok');
    end

    function browseRed()
        [f,p] = uigetfile( ...
            {'*.tif;*.tiff;*.jp2;*.png;*.jpg;*.img','Image files'}, ...
            'Select Red Band (e.g. B04)');
        if isequal(f,0), return; end
        setStatus('Loading Red band …','info'); drawnow;
        S.red = loadBand(fullfile(p,f));
        redLbl.Text = f;
        setStatus(['Red loaded: ' f '   |   Click Show RGB.'],'ok');
    end

    function browseGreen()
        [f,p] = uigetfile( ...
            {'*.tif;*.tiff;*.jp2;*.png;*.jpg;*.img','Image files'}, ...
            'Select Green Band (e.g. B03)');
        if isequal(f,0), return; end
        S.green = loadBand(fullfile(p,f));
        greenLbl.Text = f;
        setStatus(['Green loaded: ' f],'ok');
    end

    %% ----------------------------------------------------------------
    function useSampleData(scene)
        setStatus(['Generating synthetic ' scene ' scene …'],'info'); drawnow;
        switch lower(scene)
            case 'field'
                [S.nir,S.red] = syntheticField(420,420);
                S.scene = 'Agricultural Field';
            case 'ocean'
                [S.nir,S.red] = syntheticOcean(420,420);
                S.scene = 'Water Body / Ocean';
            case 'road'
                [S.nir,S.red] = syntheticRoad(420,420);
                S.scene = 'Road / Urban';
            case 'desert'
                [S.nir,S.red] = syntheticDesert(420,420);
                S.scene = 'Desert / Bare Soil';
        end
        S.ndvi=[]; S.cls=[];
        nirLbl.Text  = ['[Synthetic NIR — ' S.scene ']'];
        redLbl.Text  = ['[Synthetic Red — ' S.scene ']'];
        updateSceneLbl();
        setStatus([S.scene ' sample loaded.  Click Show RGB → Calculate NDVI.'],'ok');
    end

    %% ----------------------------------------------------------------
    function showRGB()
        if isempty(S.nir)||isempty(S.red)
            setStatus('Load images first!','err'); return; end
        setStatus('Building RGB composite …','info'); drawnow;
        if ~isempty(S.green)
            rgb = cat(3, normalizeImg(S.nir), normalizeImg(S.red), normalizeImg(S.green));
        else
            rgb = cat(3, normalizeImg(S.nir), normalizeImg(S.red), normalizeImg(S.red)*0.28);
        end
        imshow(rgb,'Parent',axRGB);
        title(axRGB,'RGB Composite  (NIR=R, Red=G, B=B or Red*0.28)', ...
            'Color',[0.85,0.85,0.85],'FontSize',10);
        setStatus('RGB ready.  Click Calculate NDVI.','ok');
    end

    %% ----------------------------------------------------------------
    function calcNDVI()
        if isempty(S.nir)||isempty(S.red)
            setStatus('Load images first!','err'); return; end
        setStatus('Applying spatial filter and computing NDVI …','info'); drawnow;

        nir_f  = applyFilter(S.nir, filterDD.Value);
        red_f  = applyFilter(S.red, filterDD.Value);
        S.ndvi = max(-1, min(1, (nir_f-red_f)./(nir_f+red_f+1e-9)));

        imagesc(axNDVI, S.ndvi, [-1,1]);
        colormap(axNDVI, ndviDivCmap(256));
        cb = colorbar(axNDVI);
        cb.Color = [0.60,0.60,0.65];
        cb.Label.String = 'NDVI';  cb.Label.Color = [0.78,0.78,0.82];
        title(axNDVI,'NDVI Map  (blue=negative | white=0 | green=high)', ...
            'Color',[0.85,0.85,0.85],'FontSize',9.5);
        axis(axNDVI,'image');
        axNDVI.XTickLabel={};  axNDVI.YTickLabel={};

        v = S.ndvi(~isnan(S.ndvi));
        maxLbl.Text  = sprintf('%.5f', max(v));
        minLbl.Text  = sprintf('%.5f', min(v));
        meanLbl.Text = sprintf('%.5f', mean(v));
        stdLbl.Text  = sprintf('%.5f', std(v));

        autoDetectScene(v);
        classify();
        setStatus(['NDVI done  |  Scene: ' S.scene ...
                   '  |  Drag threshold slider to adjust zone boundaries.'],'ok');
    end

    %% ----------------------------------------------------------------
    function onThreshChange(sl)
        S.thresh = round(sl.Value*100)/100;
        thrValLbl.Text    = sprintf('%.2f', S.thresh);
        stressBndLbl.Text = sprintf('%.2f', S.thresh/2);
        modBndLbl.Text    = sprintf('%.2f', S.thresh);
        hlthBndLbl.Text   = sprintf('%.2f', S.thresh+0.20);
        vhlthBndLbl.Text  = sprintf('%.2f', S.thresh+0.20);
        if ~isempty(S.ndvi), classify(); end
    end

    function onMethodChange()
        if ~isempty(S.ndvi), classify(); end
    end

    %% ================================================================
    %%  MAIN CLASSIFIER  — the key fixed function
    %% ================================================================
    function classify()
        if isempty(S.ndvi), return; end
        T  = S.thresh;
        method = classDD.Value;

        c = zeros(size(S.ndvi));  % 0 = background / NaN

        switch method
            % --------------------------------------------------------
            % THRESHOLD  — FIXED LOGIC
            % --------------------------------------------------------
            % Zone boundaries scale with T so every zone is ALWAYS
            % visible regardless of where the slider sits.
            %
            %   Class 1 (Water/Non-veg) : NDVI < 0
            %   Class 2 (Stressed)      : 0    ≤ NDVI < T/2
            %   Class 3 (Moderate)      : T/2  ≤ NDVI < T
            %   Class 4 (Healthy)       : T    ≤ NDVI < T+0.20
            %   Class 5 (Very Healthy)  : NDVI ≥ T+0.20
            %
            % For Ocean images:  almost all NDVI<0  → Class 1 (Water)
            % For Road images:   NDVI ~0–0.10       → Class 2 (Stressed)
            % For Desert images: NDVI ~0.05–0.20    → Class 2-3
            % --------------------------------------------------------
            case 'Threshold'
                halfT = T / 2;
                c(S.ndvi <  0)                              = 1; % Water
                c(S.ndvi >= 0      & S.ndvi < halfT)        = 2; % Stressed
                c(S.ndvi >= halfT  & S.ndvi < T)            = 3; % Moderate
                c(S.ndvi >= T      & S.ndvi < T+0.20)       = 4; % Healthy
                c(S.ndvi >= T+0.20)                         = 5; % Very Healthy
                c(isnan(S.ndvi)) = 0;

            case 'K-Means (4)'
                c = kmeansClassify(S.ndvi, 4);

            case 'K-Means (6)'
                c = kmeansClassify(S.ndvi, 6);
                % remap to max 5 for colourmap consistency
                c = min(c, 5);

            case 'Otsu (4)'
                c = otsuClassify(S.ndvi, 4);

            case 'Otsu + Water'
                c = otsuClassify(S.ndvi, 4);
                % Override: pixels with NDVI<0 become Water (class 1)
                water = S.ndvi < 0 & ~isnan(S.ndvi);
                c(water) = 1;
        end

        S.cls = c;

        imagesc(axCLS, c, [0,5]);
        colormap(axCLS, HCMAP);
        cb2 = colorbar(axCLS);
        cb2.Ticks      = 0:5;
        cb2.TickLabels = {'BG','Water','Stressed','Moderate','Healthy','V.Healthy'};
        cb2.Color      = [0.60,0.60,0.65];
        title(axCLS, ['Classification  (' method ')'], ...
            'Color',[0.85,0.85,0.85],'FontSize',10);
        axis(axCLS,'image');
        axCLS.XTickLabel={};  axCLS.YTickLabel={};

        % --- Update embedded zone histogram ---
        zLabels = {'Water','Stress','Mod','Hlth','V.Hlth'};
        counts  = arrayfun(@(k)sum(c(:)==k), 1:5);
        total   = max(1, sum(c(:)>0));
        pcts    = 100*counts / total;
        cla(axClsHist);
        bh = bar(axClsHist, 1:5, pcts, 'FaceColor','flat','EdgeColor','none');
        bh.CData = HCMAP(2:6,:);   % Water→V.Healthy colours
        axClsHist.Color      = [0.04,0.04,0.06];
        axClsHist.XColor     = [0.55,0.55,0.60];
        axClsHist.YColor     = [0.55,0.55,0.60];
        axClsHist.FontSize   = 7.5;
        axClsHist.XTick      = 1:5;
        axClsHist.XTickLabel = zLabels;
        axClsHist.XTickLabelRotation = 40;
        axClsHist.YLim       = [0, max(pcts)*1.20+1];
        ylabel(axClsHist,'%','Color',[0.60,0.60,0.65]);
        title(axClsHist,'Zone Coverage','Color',[0.70,0.70,0.75],'FontSize',8);
        % Annotate bars with percentage values
        for zi = 1:5
            if pcts(zi) > 0.5
                text(axClsHist, zi, pcts(zi)+0.8, sprintf('%.0f%%',pcts(zi)), ...
                    'HorizontalAlignment','center','Color','w','FontSize',6.5);
            end
        end

        statsTA.Value = buildStats(c, S.ndvi, method, T, S.scene);
    end

    %% ----------------------------------------------------------------
    function autoDetectScene(ndvi_vals)
        pNeg  = sum(ndvi_vals < 0)    / numel(ndvi_vals);
        pLow  = sum(ndvi_vals < 0.15) / numel(ndvi_vals);
        pHigh = sum(ndvi_vals > 0.40) / numel(ndvi_vals);
        if     pNeg  > 0.55,  S.scene = 'Water Body / Ocean';
        elseif pLow  > 0.82,  S.scene = 'Road / Urban / Bare Soil';
        elseif pHigh > 0.55,  S.scene = 'Dense Vegetation / Forest';
        elseif pHigh > 0.20,  S.scene = 'Agricultural Field';
        else,                 S.scene = 'Mixed / Semi-arid';
        end
        updateSceneLbl();
    end

    function updateSceneLbl()
        sceneLbl.Text = ['  Scene: ' S.scene];
    end

    %% ================================================================
    %%  STRESS HOTSPOT FINDER
    %% ================================================================
    function showStressHotspots()
        if isempty(S.ndvi), setStatus('Calculate NDVI first!','err'); return; end
        setStatus('Detecting stress hotspots …','info'); drawnow;

        T = S.thresh;
        % Stressed = pixels with NDVI in [0, T/2]  (mirrors the classifier)
        stressMask  = (S.ndvi >= 0) & (S.ndvi < T/2) & ~isnan(S.ndvi);
        stressClean = bwareaopen(stressMask, 30);  % remove tiny noise patches
        [L, nComp]  = bwlabel(stressClean);
        props = regionprops(L, S.ndvi, 'Area','Centroid','MeanIntensity','BoundingBox');

        hf = figure('Name','Stress Hotspot Analysis', ...
            'Position',[60,50,1400,720],'Color',[0.08,0.08,0.10]);

        % --- Panel 1: NDVI map with hotspot outlines ---
        subplot(1,3,1);
        imagesc(S.ndvi,[-1,1]); colormap(gca,ndviDivCmap(128)); colorbar;
        title(sprintf('NDVI + Stress Outlines  (T/2=%.2f)',T/2),'Color','w','FontSize',11);
        axis image off; hold on;
        bnds = bwboundaries(stressClean);
        for k=1:length(bnds)
            b=bnds{k};
            plot(b(:,2),b(:,1),'r-','LineWidth',1.8);
        end
        hold off;
        set(gca,'Color',[0.05,0.05,0.07]);

        % --- Panel 2: Stressed binary mask ---
        subplot(1,3,2);
        imagesc(double(stressClean));
        colormap(gca,[0.08,0.08,0.10; 0.92,0.18,0.10]);
        title(sprintf('Stressed Mask  (%d connected patches)',nComp),'Color','w','FontSize',11);
        axis image off;
        set(gca,'Color',[0.05,0.05,0.07]);
        % Label top 5 largest patches
        if ~isempty(props)
            [~,si]=sort([props.Area],'descend');
            top5=si(1:min(5,length(si)));
            hold on;
            for k=1:length(top5)
                cx=props(top5(k)).Centroid(1);
                cy=props(top5(k)).Centroid(2);
                text(cx,cy,sprintf('#%d\n%dpx',k,props(top5(k)).Area), ...
                    'Color','yellow','FontSize',7.5,'HorizontalAlignment','center');
            end
            hold off;
        end

        % --- Panel 3: Severity scatter (area vs mean NDVI) ---
        subplot(1,3,3);
        if ~isempty(props)
            areas    = [props.Area];
            mnNDVI   = [props.MeanIntensity];
            sc=scatter(areas,mnNDVI,max(8,areas/8),mnNDVI,'filled','MarkerEdgeColor','none');
            colormap(gca,flipud(hot(128))); colorbar;
            xlabel('Patch Area (pixels)','Color',[0.75,0.75,0.80]);
            ylabel('Mean NDVI','Color',[0.75,0.75,0.80]);
            title('Hotspot Severity','Color','w','FontSize',11);
            grid on;
            set(gca,'Color',[0.08,0.08,0.10], ...
                'XColor',[0.7,0.7,0.7],'YColor',[0.7,0.7,0.7], ...
                'GridColor',[0.22,0.22,0.25]);
            % Mark 5 worst (lowest NDVI) patches
            [~,worst]=sort(mnNDVI,'ascend');
            for k=1:min(5,length(worst))
                text(areas(worst(k)),mnNDVI(worst(k)),sprintf(' #%d',k), ...
                    'Color','white','FontSize',8);
            end
        else
            text(0.5,0.5,'No stressed patches found at this threshold.', ...
                'Color','w','HorizontalAlignment','center','Units','normalized','FontSize',12);
            axis off; set(gca,'Color',[0.08,0.08,0.10]);
        end

        % Summary stats for stressed zone
        nStressPx = sum(stressClean(:));
        nTotalPx  = sum(~isnan(S.ndvi(:)));
        sgtitle(sprintf(['Stress Hotspot Analysis  |  T/2 = %.2f  |  ' ...
            '%d patches  |  %.1f%% of scene'], ...
            T/2, nComp, 100*nStressPx/max(nTotalPx,1)), ...
            'Color','w','FontSize',13);

        setStatus(sprintf('%d stressed patches  (%.1f%% scene coverage).', ...
            nComp, 100*nStressPx/max(nTotalPx,1)),'ok');
    end

    %% ================================================================
    %%  NDVI HISTOGRAM + CDF
    %% ================================================================
    function showHistogram()
        if isempty(S.ndvi), setStatus('Calculate NDVI first!','err'); return; end
        T = S.thresh;
        v = S.ndvi(~isnan(S.ndvi));

        hf = figure('Name','NDVI Distribution & CDF', ...
            'Position',[70,70,1060,620],'Color',[0.08,0.08,0.10]);

        % --- Histogram with zone bands ---
        ax1 = subplot(1,2,1);
        edges   = linspace(-1,1,80);
        cnts    = histcounts(v,edges);
        ctrs    = (edges(1:end-1)+edges(2:end))/2;
        bar(ax1,ctrs,cnts,1.0,'FaceColor',[0.42,0.82,0.42],'EdgeColor','none');
        ymx = max(cnts)*1.15;

        % Zone shading bands
        hold(ax1,'on');
        zBands = [-1,0; 0,T/2; T/2,T; T,T+0.20; T+0.20,1];
        zColrs = {[0.10,0.25,0.85]; [0.92,0.18,0.10]; [0.98,0.80,0.10]; ...
                  [0.12,0.88,0.22]; [0.04,0.40,0.10]};
        for zi=1:5
            patch(ax1, [zBands(zi,1),zBands(zi,2),zBands(zi,2),zBands(zi,1)], ...
                       [0,0,ymx,ymx], zColrs{zi},'FaceAlpha',0.15,'EdgeColor','none');
        end
        % Boundary lines
        lineXs = [0, T/2, T, T+0.20];
        lineLbls= {'NDVI=0', sprintf('T/2=%.2f',T/2), sprintf('T=%.2f',T), ...
                   sprintf('T+.2=%.2f',T+0.20)};
        lineClrs= {[0.35,0.55,1],[1,0.45,0.25],[0.25,1,0.35],[0.15,0.80,0.15]};
        for li=1:4
            xline(ax1,lineXs(li),'--','Color',lineClrs{li},'LineWidth',1.5, ...
                'Label',lineLbls{li},'LabelColor',lineClrs{li}, ...
                'FontSize',8,'LabelHorizontalAlignment','center');
        end
        hold(ax1,'off');
        xlabel(ax1,'NDVI','Color',[0.80,0.80,0.85]);
        ylabel(ax1,'Pixel Count','Color',[0.80,0.80,0.85]);
        title(ax1,'NDVI Histogram  (coloured by zone)','Color','w','FontSize',11);
        set(ax1,'Color',[0.08,0.08,0.10],'XColor',[0.7,0.7,0.7],'YColor',[0.7,0.7,0.7]);
        xlim(ax1,[-1,1]);

        % --- CDF ---
        ax2 = subplot(1,2,2);
        vs = sort(v);
        cdf = (1:length(vs))/length(vs)*100;
        plot(ax2,vs,cdf,'-','Color',[0.30,0.80,0.30],'LineWidth',2.2);
        hold(ax2,'on');
        % Zone fills on CDF
        for li=1:4
            xline(ax2,lineXs(li),'--','Color',lineClrs{li},'LineWidth',1.5);
        end
        % Percentile markers for zone boundaries
        marks = [0, T/2, T, T+0.20];
        for m=marks
            pct = 100*mean(v<=m);
            plot(ax2,m,pct,'o','MarkerSize',7,'Color','white', ...
                'MarkerFaceColor','white');
            text(ax2,m,pct+2,sprintf('%.0f%%',pct),'Color','white', ...
                'FontSize',8,'HorizontalAlignment','center');
        end
        hold(ax2,'off');
        xlabel(ax2,'NDVI','Color',[0.80,0.80,0.85]);
        ylabel(ax2,'Cumulative Pixel %','Color',[0.80,0.80,0.85]);
        title(ax2,'Cumulative Distribution Function','Color','w','FontSize',11);
        set(ax2,'Color',[0.08,0.08,0.10],'XColor',[0.7,0.7,0.7],'YColor',[0.7,0.7,0.7]);
        xlim(ax2,[-1,1]); ylim(ax2,[0,105]);
        grid(ax2,'on'); ax2.GridColor=[0.24,0.24,0.28];

        sgtitle(sprintf('NDVI Distribution  |  μ=%.4f  σ=%.4f  |  T=%.2f  |  Scene: %s', ...
            mean(v),std(v),T,S.scene),'Color','w','FontSize',12);
        setStatus('NDVI histogram + CDF ready.','ok');
    end

    %% ================================================================
    %%  RAW vs FILTERED  COMPARISON
    %% ================================================================
    function showRawVsFiltered()
        if isempty(S.nir)||isempty(S.red)
            setStatus('Load data first!','err'); return; end
        setStatus('Computing NDVI for all 5 filters …','info'); drawnow;

        fnames = {'None','Gaussian','Median','Wiener','Bilateral-like'};
        nf     = length(fnames);
        ndvi_f = cell(1,nf);
        for k=1:nf
            nr = applyFilter(S.nir,fnames{k});
            rr = applyFilter(S.red,fnames{k});
            ndvi_f{k} = max(-1,min(1,(nr-rr)./(nr+rr+1e-9)));
        end

        hf = figure('Name','Raw vs Filtered NDVI', ...
            'Position',[50,50,1500,720],'Color',[0.08,0.08,0.10]);
        bclrs = {[0.95,0.40,0.30],[0.28,0.78,0.38],[0.28,0.68,0.98], ...
                 [0.98,0.78,0.18],[0.80,0.30,0.80]};

        for k=1:nf
            subplot(2,nf,k);
            imagesc(ndvi_f{k},[-1,1]); colormap(gca,ndviDivCmap(128)); colorbar;
            title(fnames{k},'Color','w','FontSize',10);
            axis image off;
            set(gca,'Color',[0.05,0.05,0.07]);

            subplot(2,nf,nf+k);
            vv = ndvi_f{k}(~isnan(ndvi_f{k}));
            histogram(vv,60,'FaceColor',bclrs{k},'EdgeColor','none','FaceAlpha',0.88);
            xlabel('NDVI','Color',[0.7,0.7,0.7]);
            ylabel('Count','Color',[0.7,0.7,0.7]);
            set(gca,'Color',[0.08,0.08,0.10],'XColor',[0.7,0.7,0.7],'YColor',[0.7,0.7,0.7]);
            text(0.05,0.88,sprintf('μ=%.3f\nσ=%.3f',mean(vv),std(vv)), ...
                'Units','normalized','Color','w','FontSize',8.5);
        end

        sgtitle('Raw vs Filtered NDVI  (map + histogram)','Color','w','FontSize',13);
        setStatus('Filter comparison ready.','ok');
    end

    %% ================================================================
    %%  INDEX COMPARISON  (NDVI / EVI / SAVI / MSAVI / GNDVI / RENDVI)
    %% ================================================================
    function compareIndices()
        if isempty(S.nir)||isempty(S.red)
            setStatus('Load data first!','err'); return; end
        setStatus('Computing 6 vegetation indices …','info'); drawnow;

        nir = applyFilter(S.nir,'Gaussian');
        red = applyFilter(S.red,'Gaussian');
        g   = S.green;
        if isempty(g), g = red*0.80; end  % fallback: approximate green
        g   = applyFilter(g,'Gaussian');

        NDVI   = max(-1,min(1, (nir-red)./(nir+red+1e-9)));
        L=0.5;
        SAVI   = max(-1,min(1, ((nir-red)./(nir+red+L+1e-9))*(1+L)));
        EVI    = max(-1,min(1, 2.5*(nir-red)./(nir+6*red-7.5*0.05+1+1e-9)));
        MSAVI  = max(-1,min(1, (2*nir+1-sqrt(max(0,(2*nir+1).^2-8*(nir-red))))/2));
        GNDVI  = max(-1,min(1, (nir-g)./(nir+g+1e-9)));
        % Red-Edge NDVI approximation (Sentinel-2 lacks B5 here, use scaled NIR)
        nir_re = min(1, nir*1.08);
        RENDVI = max(-1,min(1, (nir_re-red)./(nir_re+red+1e-9)));

        idxs  = {NDVI,EVI,SAVI,MSAVI,GNDVI,RENDVI};
        names = {'NDVI','EVI','SAVI','MSAVI','GNDVI','RE-NDVI'};
        cmaps = {'jet','hot','cool','parula','summer','winter'};

        hf = figure('Name','Vegetation Index Comparison', ...
            'Position',[50,50,1560,760],'Color',[0.08,0.08,0.10]);
        for k=1:6
            subplot(2,6,k);
            imagesc(idxs{k},[-1,1]); colormap(gca,cmaps{k}); colorbar;
            title([names{k} ' Map'],'Color','w','FontSize',10);
            axis image off; set(gca,'Color',[0.05,0.05,0.07]);

            subplot(2,6,6+k);
            vv=idxs{k}(~isnan(idxs{k}));
            histogram(vv,60,'FaceAlpha',0.85,'EdgeColor','none');
            title([names{k} ' Dist.'],'Color','w','FontSize',9);
            xlabel('Value','Color',[0.7,0.7,0.7]);
            ylabel('Pixels','Color',[0.7,0.7,0.7]);
            set(gca,'Color',[0.08,0.08,0.10],'XColor',[0.7,0.7,0.7],'YColor',[0.7,0.7,0.7]);
            text(0.04,0.88,sprintf('μ=%.3f\nσ=%.3f',mean(vv),std(vv)), ...
                'Units','normalized','Color','w','FontSize',8);
        end
        sgtitle('Vegetation Indices: NDVI | EVI | SAVI | MSAVI | GNDVI | RE-NDVI', ...
            'Color','w','FontSize',13);
        setStatus('Index comparison ready.','ok');
    end

    %% ================================================================
    %%  COMPARE ALL METHODS + CONFUSION MATRICES
    %% ================================================================
    function compareAllMethods()
        if isempty(S.ndvi), setStatus('Calculate NDVI first!','err'); return; end
        setStatus('Running all classifiers and building confusion matrices …','info');
        drawnow;

        T_ref = 0.30;   % reference threshold (ground-truth proxy)
        T_cur = S.thresh;
        labels= {'Water','Stress','Mod','Healthy','V.Hlth'};
        cls5  = 1:5;

        c_ref = threshClassify5(S.ndvi, T_ref);
        c_km4 = kmeansClassify(S.ndvi, 4);
        c_km6 = min(kmeansClassify(S.ndvi,6), 5);
        c_ot  = otsuClassify(S.ndvi, 4);
        c_cur = threshClassify5(S.ndvi, T_cur);

        gt = c_ref(c_ref>0);
        function [acc,f1m,CM] = evalMethod(cpred)
            p  = cpred(c_ref>0);
            CM = confMat_n(gt,p,cls5);
            [acc,~,~,f1] = compMetrics(CM);
            f1m = mean(f1);
        end

        [acc_ref,f1_ref,CM_ref] = evalMethod(c_ref);
        [acc_km4,f1_km4,CM_km4] = evalMethod(c_km4);
        [acc_km6,f1_km6,CM_km6] = evalMethod(c_km6);
        [acc_ot, f1_ot, CM_ot ] = evalMethod(c_ot);
        [acc_cur,f1_cur,CM_cur] = evalMethod(c_cur);

        scr  = get(0,'ScreenSize');
        figW = min(1440, scr(3) - 40);
        figH = min(870,  scr(4) - 80);
        hf = figure('Name','Method Comparison & Confusion Matrices', ...
            'Position',[max(10,(scr(3)-figW)/2), max(10,(scr(4)-figH)/2), figW, figH], ...
            'Color',[0.08,0.08,0.10]);

        maps   = {c_ref, c_km4, c_km6, c_ot, c_cur};
        mnames = {sprintf('Reference (T=%.2f)',T_ref), 'K-Means 4', ...
                  'K-Means 6','Otsu 4',sprintf('Current (T=%.2f)',T_cur)};
        accs   = [acc_ref, acc_km4, acc_km6, acc_ot, acc_cur];
        f1s    = [f1_ref,  f1_km4,  f1_km6,  f1_ot,  f1_cur];

        % Row 1: classification maps
        for k=1:5
            subplot(4,6,k);
            imagesc(maps{k},[0,5]); colormap(gca,HCMAP);
            title(mnames{k},'Color','w','FontSize',9,'Interpreter','none');
            axis image off; set(gca,'Color',[0.05,0.05,0.07]);
        end

        % Accuracy bar
        subplot(4,6,6);
        bc=bar(accs,'FaceColor','flat');
        bcolrs=[0.28,0.78,0.38; 0.28,0.58,0.98; 0.70,0.30,0.90; ...
                0.98,0.68,0.18; 0.80,0.30,0.30];
        bc.CData=bcolrs;
        set(gca,'XTickLabel',{'Ref','KM4','KM6','Ots','Cur'}, ...
            'Color',[0.08,0.08,0.10],'XColor','w','YColor','w','FontSize',8);
        title('Accuracy %','Color','w','FontSize',9); ylim([0,115]);
        for i=1:5, text(i,accs(i)+1,sprintf('%.0f%%',accs(i)), ...
            'HorizontalAlignment','center','Color','w','FontSize',7.5); end

        % Row 2: F1 bar + Confusion for KM4 + Confusion for Otsu
        subplot(4,6,7);
        bc2=bar(f1s,'FaceColor','flat'); bc2.CData=bcolrs;
        set(gca,'XTickLabel',{'Ref','KM4','KM6','Ots','Cur'}, ...
            'Color',[0.08,0.08,0.10],'XColor','w','YColor','w','FontSize',8);
        title('Mean F1','Color','w','FontSize',9); ylim([0,1.2]);
        for i=1:5, text(i,f1s(i)+0.02,sprintf('%.2f',f1s(i)), ...
            'HorizontalAlignment','center','Color','w','FontSize',7.5); end

        subplot(4,6,[8,9,14,15]);
        plotCM(CM_km4, labels, 'K-Means 4 vs Reference');

        subplot(4,6,[10,11,16,17]);
        plotCM(CM_ot, labels, 'Otsu 4 vs Reference');

        subplot(4,6,[12,13,18,19]);
        plotCM(CM_cur, labels, sprintf('Current Threshold (%.2f) vs Ref',T_cur));

        % Row 3-4: per-class metrics
        [~,p_ref,r_ref,f_ref] = compMetrics(CM_ref);
        [~,p_km4,r_km4,f_km4] = compMetrics(CM_km4);
        [~,p_ot, r_ot, f_ot ] = compMetrics(CM_ot);
        [~,p_cur,r_cur,f_cur] = compMetrics(CM_cur);

        subplot(4,6,[19,20]);
        plotPerClassBar({p_ref,p_km4,p_ot,p_cur},{'Ref','KM4','Ots','Cur'},labels,'Precision');

        subplot(4,6,[21,22]);
        plotPerClassBar({r_ref,r_km4,r_ot,r_cur},{'Ref','KM4','Ots','Cur'},labels,'Recall');

        subplot(4,6,[23,24]);
        plotPerClassBar({f_ref,f_km4,f_ot,f_cur},{'Ref','KM4','Ots','Cur'},labels,'F1 Score');

        sgtitle(sprintf('Method Comparison  |  Reference T=%.2f  |  Scene: %s', ...
            T_ref, S.scene),'Color','w','FontSize',12);
        setStatus('Method comparison complete.','ok');
    end

    %% ================================================================
    %%  EXPORT
    %% ================================================================
    function exportResults()
        if isempty(S.cls), setStatus('Run NDVI first!','err'); return; end
        [fname,fpath]=uiputfile({'*.csv','CSV Report'},'Save','crop_health_report.csv');
        if isequal(fname,0), return; end

        v     = S.ndvi(~isnan(S.ndvi));
        total = max(1, sum(S.cls(:)>0));
        labs  = {'Water/Non-veg','Stressed','Moderate','Healthy','Very Healthy'};
        counts= arrayfun(@(c)sum(S.cls(:)==c), 1:5);
        pcts  = 100*counts/total;

        % Per-zone mean NDVI
        mnNDVI = zeros(1,5);
        for zi=1:5
            mask = S.cls==zi & ~isnan(S.ndvi);
            if any(mask(:)), mnNDVI(zi)=mean(S.ndvi(mask)); end
        end
        stressRatio = 100*counts(2)/max(sum(counts(2:5)),1);

        fid = fopen(fullfile(fpath,fname),'w');
        fprintf(fid,'Crop Health Monitor v4.0 — Export Report\n');
        fprintf(fid,'Generated,%s\n',datestr(now));
        fprintf(fid,'Scene Type,%s\n',S.scene);
        fprintf(fid,'Method,%s\n',classDD.Value);
        fprintf(fid,'Threshold T,%.4f\n',S.thresh);
        fprintf(fid,'Stressed Zone Upper Bound (T/2),%.4f\n',S.thresh/2);
        fprintf(fid,'\nNDVI Statistics\n');
        fprintf(fid,'Max,%.5f\nMin,%.5f\nMean,%.5f\nStd,%.5f\n', ...
            max(v),min(v),mean(v),std(v));
        fprintf(fid,'\nStress Ratio (%%  of vegetated pixels),%.2f%%\n',stressRatio);
        fprintf(fid,'\nHealth Zone,Pixels,Percentage,Mean NDVI\n');
        for i=1:5
            fprintf(fid,'%s,%d,%.2f,%.4f\n',labs{i},counts(i),pcts(i),mnNDVI(i));
        end
        fclose(fid);

        % Save classification PNG
        [~,base] = fileparts(fname);
        pngPath  = fullfile(fpath,[base '_classification.png']);
        hf2 = figure('Visible','off','Position',[0,0,1000,800],'Color','k');
        imagesc(S.cls,[0,5]); colormap(HCMAP);
        cb3=colorbar; cb3.Ticks=0:5;
        cb3.TickLabels={'BG','Water','Stressed','Moderate','Healthy','V.Healthy'};
        cb3.Color='w';
        title(sprintf('Crop Health Map  |  T=%.2f  |  Scene: %s', S.thresh,S.scene), ...
            'Color','w','FontSize',13);
        axis image off;
        saveas(hf2,pngPath); close(hf2);

        setStatus(['Exported  →  ' fname '  +  ' base '_classification.png'],'ok');
    end

    %% ----------------------------------------------------------------
    function setStatus(msg,kind)
        clrs=struct('ok',[0.32,0.90,0.32],'err',[1,0.28,0.28],'info',[0.32,0.70,1]);
        if isfield(clrs,kind), statusLbl.FontColor=clrs.(kind); end
        statusLbl.Text = ['  ' msg]; drawnow;
    end

    %% ================================================================
    %%  imgPanel factory  (nested so it can stay inline)
    %% ================================================================
    function [ax,hb] = makeImgPanel(xp, stpTxt, btnTxt, cb, btnClr)
        if nargin<5, btnClr=BTN; end
        p = uipanel(fig,'Position',[xp,iY,iW,iH], ...
            'BackgroundColor',[0.06,0.06,0.08], ...
            'ForegroundColor',[0.40,0.40,0.46]);
        uilabel(p,'Text',stpTxt,'Position',[5,iH-26,iW-160,22], ...
            'FontSize',8.8,'FontColor',[0.52,0.52,0.58], ...
            'BackgroundColor',[0.06,0.06,0.08]);
        hb = uibutton(p,'push','Text',btnTxt, ...
            'Position',[iW-152,iH-28,148,24], ...
            'FontSize',9,'FontWeight','bold', ...
            'BackgroundColor',btnClr,'FontColor',FG,'ButtonPushedFcn',cb);
        ax = uiaxes(p,'Position',[2,2,iW-4,iH-36], ...
            'Color',[0.04,0.04,0.06], ...
            'XColor',[0.28,0.28,0.32],'YColor',[0.28,0.28,0.32], ...
            'XTickLabel',{},'YTickLabel',{});
    end

end % ========== end CropHealthMonitor ==========


%% =========================================================================
%%  LOCAL HELPER FUNCTIONS
%% =========================================================================

% ── loadBand ─────────────────────────────────────────────────────────────
function band = loadBand(fp)
    raw = imread(fp);
    if size(raw,3)>1, raw=raw(:,:,1); end
    band = double(raw);
    if max(band(:))>1000,    band=band/10000;
    elseif max(band(:))>1,   band=band/max(band(:)); end
    band = max(0,min(1,band));
end

% ── normalizeImg ─────────────────────────────────────────────────────────
function out = normalizeImg(img)
    lo=min(img(:)); hi=max(img(:));
    if hi==lo, out=zeros(size(img)); return; end
    out=(img-lo)/(hi-lo);
end

% ── applyFilter ──────────────────────────────────────────────────────────
function out = applyFilter(img, ftype)
    switch ftype
        case 'Gaussian'
            out = imfilter(img, fspecial('gaussian',[5,5],1.5), 'replicate');
        case 'Median'
            out = medfilt2(img,[3,3]);
        case 'Wiener'
            out = wiener2(img,[5,5]);
        case 'Bilateral-like'
            % Approximate bilateral: detail-preserving smoothing
            smooth_s = imgaussfilt(img,1.2);
            smooth_l = imgaussfilt(img,4.0);
            out = smooth_s + 0.45*(img - smooth_l);
            out = max(0,min(1,out));
        otherwise
            out = img;
    end
end

% ── ndviDivCmap  (diverging: blue → white → green) ───────────────────────
function cmap = ndviDivCmap(n)
    half = floor(n/2);
    neg  = [linspace(0.05,1,half)', linspace(0.10,1,half)', linspace(0.65,1,half)'];
    pos  = [linspace(1,0.02,n-half)', linspace(1,0.52,n-half)', linspace(1,0.04,n-half)'];
    cmap = [neg; pos];
end

% ── threshClassify5  (the FIXED 5-class threshold function) ───────────────
%
%   Class 1 Water     : NDVI < 0
%   Class 2 Stressed  : 0  ≤ NDVI < T/2
%   Class 3 Moderate  : T/2≤ NDVI < T
%   Class 4 Healthy   : T  ≤ NDVI < T+0.20
%   Class 5 V.Healthy : NDVI ≥ T+0.20
%   Class 0 Background: NaN pixels
%
function c = threshClassify5(ndvi, T)
    halfT = T/2;
    c = zeros(size(ndvi));
    c(ndvi <  0)                        = 1;  % Water / Non-veg
    c(ndvi >= 0    & ndvi < halfT)      = 2;  % Stressed
    c(ndvi >= halfT& ndvi < T)          = 3;  % Moderate
    c(ndvi >= T    & ndvi < T+0.20)     = 4;  % Healthy
    c(ndvi >= T+0.20)                   = 5;  % Very Healthy
    c(isnan(ndvi)) = 0;
end

% ── kmeansClassify ────────────────────────────────────────────────────────
function c = kmeansClassify(ndvi, nCls)
    flat  = ndvi(:);
    valid = ~isnan(flat);
    [idx,C] = kmeans(flat(valid), nCls, 'Replicates',3,'MaxIter',300);
    [~,ord] = sort(C);
    rnk = zeros(nCls,1); rnk(ord)=1:nCls;
    c = zeros(size(ndvi));
    c(valid) = rnk(idx);
end

% ── otsuClassify ─────────────────────────────────────────────────────────
function c = otsuClassify(ndvi, nThr)
    vv = ndvi(~isnan(ndvi));
    lo=min(vv); hi=max(vv);
    nm = (ndvi-lo)/(hi-lo+1e-9);
    T3 = multithresh(nm(~isnan(nm)), nThr);
    c  = double(imquantize(nm, T3));
    c(isnan(ndvi)) = 0;
end

% ── confMat_n ─────────────────────────────────────────────────────────────
function CM = confMat_n(gt, pred, classes)
    n=length(classes); CM=zeros(n,n);
    for i=1:n, for j=1:n
        CM(i,j)=sum(gt==classes(i) & pred==classes(j));
    end, end
end

% ── compMetrics ──────────────────────────────────────────────────────────
function [acc,prec,rec,f1] = compMetrics(CM)
    n=size(CM,1); tot=sum(CM(:));
    acc=100*sum(diag(CM))/max(tot,1);
    prec=zeros(1,n); rec=zeros(1,n); f1=zeros(1,n);
    for i=1:n
        tp=CM(i,i); fp=sum(CM(:,i))-tp; fn=sum(CM(i,:))-tp;
        prec(i)=tp/max(tp+fp,1);
        rec(i) =tp/max(tp+fn,1);
        f1(i)  =2*prec(i)*rec(i)/max(prec(i)+rec(i),1e-9);
    end
end

% ── plotCM ───────────────────────────────────────────────────────────────
function plotCM(CM, labels, ttl)
    n=size(CM,1);
    CMn=CM./max(sum(CM,2),1);
    imagesc(CMn,[0,1]); colormap(gca,flipud(gray)); colorbar;
    set(gca,'XTick',1:n,'YTick',1:n, ...
        'XTickLabel',labels,'YTickLabel',labels, ...
        'XColor','w','YColor','w','Color',[0.05,0.05,0.07],'FontSize',7.5);
    xlabel('Predicted','Color','w'); ylabel('Actual','Color','w');
    title(ttl,'Color','w','FontSize',9,'Interpreter','none');
    for i=1:n, for j=1:n
        clr='w'; if CMn(i,j)>0.5, clr='k'; end
        text(j,i,sprintf('%.2f',CMn(i,j)), ...
            'HorizontalAlignment','center','Color',clr,'FontSize',7.5);
    end, end
end

% ── plotPerClassBar ───────────────────────────────────────────────────────
function plotPerClassBar(vals_cell, methodLabels, classLabels, metricName)
    nM=length(vals_cell); nC=length(classLabels);
    data=zeros(nC,nM);
    for m=1:nM, data(:,m)=vals_cell{m}(1:nC)'; end
    b=bar(data,'grouped');
    bcolrs=[0.28,0.88,0.38; 0.28,0.58,0.98; 0.98,0.72,0.18; 0.80,0.30,0.30];
    for m=1:min(nM,4), b(m).FaceColor=bcolrs(m,:); end
    set(gca,'XTickLabel',classLabels,'Color',[0.08,0.08,0.10], ...
        'XColor','w','YColor','w','FontSize',7.5);
    ylabel(metricName,'Color','w'); title(metricName,'Color','w','FontSize',9);
    ylim([0,1.18]);
    legend(methodLabels,'TextColor','w','Color',[0.12,0.12,0.15], ...
        'FontSize',7,'Location','northoutside','Orientation','horizontal');
end

% ── buildStats ───────────────────────────────────────────────────────────
function lines = buildStats(cls, ndvi, method, T, scene)
    v     = ndvi(~isnan(ndvi));
    total = max(1, sum(cls(:)>0));
    zNames= {'Water/Non-veg','Stressed','Moderate','Healthy','Very Healthy'};
    counts= arrayfun(@(c)sum(cls(:)==c), 1:5);
    pcts  = 100*counts/total;
    mnNDVI= zeros(1,5);
    for zi=1:5
        m=cls==zi & ~isnan(ndvi);
        if any(m(:)), mnNDVI(zi)=mean(ndvi(m)); end
    end
    vegTot = max(sum(counts(2:5)),1);
    stressRatio = 100*counts(2)/vegTot;
    sep='─────────────────────────────────────────────────────────';
    lines={sep, ...
        sprintf('  Method: %-20s   T = %.2f', method, T), ...
        sprintf('  Scene : %s', scene), sep, ...
        sprintf('  NDVI Max  : %+.5f     Min : %+.5f', max(v), min(v)), ...
        sprintf('  NDVI Mean : %+.5f     Std :  %.5f', mean(v), std(v)), sep, ...
        '  Zone Coverage  (pixels | % | mean NDVI):', ...
        sprintf('  [1] %-14s : %6d px  %5.1f%%   μ=%+.3f', zNames{1},counts(1),pcts(1),mnNDVI(1)), ...
        sprintf('  [2] %-14s : %6d px  %5.1f%%   μ=%+.3f', zNames{2},counts(2),pcts(2),mnNDVI(2)), ...
        sprintf('  [3] %-14s : %6d px  %5.1f%%   μ=%+.3f', zNames{3},counts(3),pcts(3),mnNDVI(3)), ...
        sprintf('  [4] %-14s : %6d px  %5.1f%%   μ=%+.3f', zNames{4},counts(4),pcts(4),mnNDVI(4)), ...
        sprintf('  [5] %-14s : %6d px  %5.1f%%   μ=%+.3f', zNames{5},counts(5),pcts(5),mnNDVI(5)), sep, ...
        sprintf('  Stress Ratio (of vegetated px) : %.1f%%', stressRatio), ...
        sprintf('  Boundaries : Water<0 | Stressed<%.2f | Moderate<%.2f | Healthy<%.2f', ...
            T/2, T, T+0.20), sep};
end

%% =========================================================================
%%  SYNTHETIC SCENE GENERATORS
%% =========================================================================

% ── Agricultural field ───────────────────────────────────────────────────
function [nir,red] = syntheticField(rows,cols)
    [X,Y]=meshgrid(linspace(0,1,cols),linspace(0,1,rows)); rng(42);
    base=0.55+0.25*sin(3.5*pi*X).*cos(2.5*pi*Y)+0.15*cos(5*pi*X.*Y);
    s1=0.55*exp(-((X-.18).^2+(Y-.25).^2)/.012);
    s2=0.45*exp(-((X-.72).^2+(Y-.68).^2)/.009);
    s3=0.50*exp(-((X-.50).^2+(Y-.12).^2)/.007);
    s4=0.35*exp(-((X-.85).^2+(Y-.35).^2)/.006);
    hz=0.30*exp(-((X-.50).^2+(Y-.55).^2)/.035);
    nir=base+hz-0.4*s1-0.35*s2-0.30*s3-0.25*s4+0.04*randn(rows,cols);
    red=0.55-0.38*base-hz+0.40*s1+0.35*s2+0.30*s3+0.22*s4+0.04*randn(rows,cols);
    h=fspecial('gaussian',[9,9],2.5);
    nir=max(0.01,min(0.99,imfilter(nir,h,'replicate')));
    red=max(0.01,min(0.99,imfilter(red,h,'replicate')));
end

% ── Ocean / water body ────────────────────────────────────────────────────
% NIR is very low (water absorbs NIR strongly); Red slightly higher.
% Result: NDVI strongly negative across most of image → class 1 (Water).
% Small land strip at one edge with moderate vegetation.
function [nir,red] = syntheticOcean(rows,cols)
    [X,Y]=meshgrid(linspace(0,1,cols),linspace(0,1,rows)); rng(7);
    % Open water: NIR ≈ 0.03-0.06, Red ≈ 0.07-0.12  → NDVI ≈ -0.3 to -0.5
    nir = 0.04 + 0.015*randn(rows,cols) + 0.012*sin(10*pi*X).*sin(8*pi*Y);
    red = 0.09 + 0.018*randn(rows,cols) + 0.020*sin(6*pi*X).*cos(9*pi*Y);
    % Shallow water / sediment plume (slightly higher red reflectance)
    sed1 = 0.08*exp(-((X-.35).^2+(Y-.65).^2)/.018);
    sed2 = 0.06*exp(-((X-.70).^2+(Y-.25).^2)/.012);
    red  = red + sed1 + sed2;
    % Thin coastal strip on left edge with sparse vegetation
    % (produces Stressed + Moderate pixels for contrast)
    coast = X < 0.10;
    nir(coast) = 0.25 + 0.08*randn(sum(coast(:)),1);
    red(coast) = 0.14 + 0.05*randn(sum(coast(:)),1);
    % Small island near centre
    island = sqrt((X-0.55).^2+(Y-0.45).^2) < 0.06;
    nir(island) = 0.50 + 0.06*randn(sum(island(:)),1);
    red(island) = 0.10 + 0.04*randn(sum(island(:)),1);
    h=fspecial('gaussian',[7,7],2.0);
    nir=max(0.005,min(0.99,imfilter(nir,h,'replicate')));
    red=max(0.005,min(0.99,imfilter(red,h,'replicate')));
end

% ── Road / urban scene ────────────────────────────────────────────────────
% Roads: NIR ≈ 0.10, Red ≈ 0.15  → NDVI ≈ -0.2 to 0  (Stressed/Water)
% Buildings: moderate NIR & Red  → NDVI ≈ 0.05-0.15   (Stressed)
% Small parks: higher NIR        → NDVI ≈ 0.25-0.40   (Moderate/Healthy)
function [nir,red] = syntheticRoad(rows,cols)
    [X,Y]=meshgrid(linspace(0,1,cols),linspace(0,1,rows)); rng(13);
    % Urban base: moderate reflectance, NDVI near zero
    nir = 0.20 + 0.07*randn(rows,cols);
    red = 0.19 + 0.06*randn(rows,cols);
    % Road grid pattern (asphalt: low NIR, low-moderate Red)
    road_h = abs(sin(pi*Y*7)) < 0.07;
    road_v = abs(sin(pi*X*7)) < 0.07;
    roads  = road_h | road_v;
    nir(roads) = 0.08 + 0.025*randn(sum(roads(:)),1);
    red(roads) = 0.14 + 0.028*randn(sum(roads(:)),1);
    % Building blocks (high reflectance, NDVI ~0.05-0.12)
    bld = (mod(floor(X*7),2)==0) & (mod(floor(Y*7),2)==0) & ~roads;
    nir(bld) = 0.28 + 0.06*randn(sum(bld(:)),1);
    red(bld) = 0.24 + 0.05*randn(sum(bld(:)),1);
    % Small park patches (NDVI ~0.30-0.50 → Moderate / Healthy)
    park1 = exp(-((X-.52).^2+(Y-.48).^2)/.012);
    park2 = exp(-((X-.20).^2+(Y-.75).^2)/.009);
    park3 = exp(-((X-.78).^2+(Y-.22).^2)/.007);
    nir = nir + 0.32*park1 + 0.28*park2 + 0.25*park3;
    red = red  - 0.10*park1 - 0.09*park2 - 0.08*park3;
    h=fspecial('gaussian',[5,5],1.8);
    nir=max(0.01,min(0.99,imfilter(nir,h,'replicate')));
    red=max(0.01,min(0.99,imfilter(red,h,'replicate')));
end

% ── Desert / bare soil ────────────────────────────────────────────────────
% Bare soil: NIR ≈ 0.25-0.35, Red ≈ 0.22-0.32  → NDVI ≈ 0.05-0.20 (Stressed)
% Sparse scrub patches → NDVI ≈ 0.15-0.28 (Stressed/Moderate)
% Dry riverbed: NDVI slightly negative → Water/Stressed
function [nir,red] = syntheticDesert(rows,cols)
    [X,Y]=meshgrid(linspace(0,1,cols),linspace(0,1,rows)); rng(21);
    % Sand / bare soil
    nir = 0.32 + 0.10*randn(rows,cols) + 0.08*sin(4*pi*X).*cos(3.5*pi*Y);
    red = 0.29 + 0.09*randn(rows,cols) + 0.07*cos(5*pi*X).*sin(4*pi*Y);
    % Sparse vegetation patches (acacia / scrub)
    v1=0.28*exp(-((X-.28).^2+(Y-.62).^2)/.010);
    v2=0.22*exp(-((X-.72).^2+(Y-.30).^2)/.008);
    v3=0.18*exp(-((X-.50).^2+(Y-.80).^2)/.006);
    v4=0.14*exp(-((X-.15).^2+(Y-.15).^2)/.005);
    vegSum=v1+v2+v3+v4;
    nir = nir + vegSum;
    red = red - 0.18*vegSum;
    % Dry riverbed (sinuous, low reflectance → NDVI slightly negative)
    riverCtr = 0.50 + 0.18*sin(3*pi*Y);
    river = abs(X - riverCtr) < 0.03;
    nir(river) = 0.12 + 0.03*randn(sum(river(:)),1);
    red(river) = 0.16 + 0.03*randn(sum(river(:)),1);
    % Salt flat patch (very high Red, low NIR → strongly negative NDVI)
    salt = exp(-((X-.85).^2+(Y-.75).^2)/.006);
    nir  = nir - 0.08*salt;
    red  = red  + 0.12*salt;
    h=fspecial('gaussian',[9,9],2.5);
    nir=max(0.005,min(0.99,imfilter(nir,h,'replicate')));
    red=max(0.005,min(0.99,imfilter(red,h,'replicate')));
end