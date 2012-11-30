class InteractionController < ApplicationController

  # module for instructor to view all interactions
  def instructor_view

    @teams=Team.find_all_by_parent_id(params[:id])    # get all teams in curent assignment
    @interactions=Array.new
    @participant_helped=Array.new
    @team_helped=Array.new
                                                      #get all interactions of all teams
    for team in @teams
      @participant_helped += HelperInteraction.find_all_by_team_id(team.id)
      @team_helped += HelpeeInteraction.find_all_by_team_id(team.id)
    end
    render  'instructor_view', :id=>params[:id],:locals => {:id=>params[:id],:expanded => (params[:expanded])}
  end

  def view
    puts "Entered controller for interaction"
    @participant = AssignmentParticipant.find(params[:id])
    return unless current_user_id?(@participant.user_id)
    @participant_helps = HelperInteraction.find_interactions(params[:id])
    @participant_helped = HelpeeInteraction.find_interactions(params[:id])
    @assignment=params[:assignment]
  end

  # generate the tuple entries for the current interaction form in the Interaction table
  def create
    ###################################################
    #Add the values to the Scores, Response and ResponseMap tables.
    puts "Entered create"
    @assignment = Assignment.find(params[:assign])

    if(params[:type] == "helpee")  #Response created by the helpee. So both reviewer and reviewee are users
      helperid = User.find_by_name(params[:helper]).id
      @reviewerid = Participant.first(:conditions => ['parent_id = ? and user_id = ?',params[:assign],helperid]).id
      @revieweeid = Team.find(Participant.find(session[:participant_id]).team.id).id
    elsif(params[:type] == "helper") #Response created by helper. So the reviewee is a team
      @reviewerid = session[:participant_id]
      @revieweeid=Team.first(:conditions => ['parent_id=? and name=?',params[:assign],params[:teams]]).id
    end
    puts "The id of assignment"
    puts @assignment.id
    puts "The id of reviewer"
    puts @reviewerid
    puts "The id of reviewee"
    puts @revieweeid
    puts "Creating map now"
    map = InteractionResponseMap.create(:reviewed_object_id=>@assignment.id,:reviewer_id=>@reviewerid,:reviewee_id=>@revieweeid)
    @response = Response.create(:map_id=>map.id,:additional_comment=>params[:review][:comments])
    puts "Created database entries for map and response"
    @questionnaire = Questionnaire.find(params[:questionnaire_id])
    puts "Identified the questionnaire"
    questions = @questionnaire.questions
    params[:responses].each_pair do |k,v|
      score = Score.create(:response_id => @response.id, :question_id => questions[k.to_i].id, :score => v[:score], :comments => v[:comment])
      if(questions[k.to_i].txt == "Score")
        puts "Score question. Score is "
        puts v[:score]
        @actualscore = v[:score]
      end
    end
    puts "Created database entries for scores"
    ###################################################
    #Older implementation starts here. Certain parts of it are redundant and need to be removed
    @curr_participant = session[:participant_id]
    # for helpee entries into the table
    if(params[:type]=="helpee")
      #@user = User.find_by_name(params[:helper])
      #Find the user by his login instead of his name
      @user = User.find_by_name(params[:helper])
      p params[:helper]
      # if username wrong then error displayed and redirected to a new form again
      if !@user
        if params[:helper].to_s == ""
          @error = "Username cannot be blank."
        else
          @error = "User \"" + params[:helper].to_s +  "\" does not exist."
        end

        @user_name = params[:helper].to_s
        @user_name = @user.name.to_s
        @assignment = params[:assign]
        @type = params[:type]
        @id = session[:participant_id]
        @participant_id = session[:participant_id]
        @my_team_id = Participant.find(@participant_id).team.id
        @my_team = Team.find(@my_team_id)
        @interaction = HelpeeInteraction.new(params[:interactions])
        @advices = InteractionAdvice.find_all_by_assignment_id(params[:assignment_id])
        @advices = @advices.sort{|x,y|x.score<=>y.score}
        flash[:alert] = @error
        render :action => 'new' ,
               :assignment_id=>params[:assign], :type=>params[:type], :id=>session[:participant_id], :interaction => @interaction
      else
        @helper_user = @user.id
        @helper_assignment= params[:assign]
        @helper_participant=Participant.first(:conditions => ['parent_id = ? and user_id = ?',params[:assign],@helper_user])
        @selected_team=Team.find(Participant.find(session[:participant_id]).team.id)
        @helpee_record = HelpeeInteraction.first(:conditions => ["participant_id = ? AND team_id = ?", @helper_participant, @selected_team.id])
        if !TeamsUser.first(:conditions => ['team_id = ? and user_id = ?', @selected_team.id, @helper_user])

          # check if current helpee interaction already exists
          if !@helpee_record
            @interaction = HelpeeInteraction.new(params[:interactions])
            @interaction.interaction_datetime = params[:interaction_date]
            @interaction.team_id = @selected_team.id
            #@interaction.score = params[:score]
            @interaction.score = @actualscore
            @interaction.participant_id=@helper_participant.id
            @interaction.status='Not Confirmed'

            # on save check if helper has already filled the form.If yes then set status of helper and helpee to 'Confirmed'
            if @interaction.save
              @helper_record = HelperInteraction.first(:conditions => ["participant_id = ? AND team_id = ?",
                                                                       @interaction.participant_id,@interaction.team_id ])
              if @helper_record
                @helpee_record=HelpeeInteraction.first(:conditions => ["participant_id = ? AND team_id = ?",
                                                                       @interaction.participant_id,@interaction.team_id ])
                @helpee_record.update_attribute('status','Confirmed')
                @helper_record.update_attribute('status','Confirmed')
              end
              flash[:note] =" Interaction created successfully."
              redirect_to :controller=>'interaction', :action=>'view',:assignment=>params[:assign], :id=>session[:participant_id]
            else
              @error = ""
              @assignment = params[:assign]
              @user_name = params[:helper].to_s
              @type = params[:type]
              @id = session[:participant_id]
              @participant_id = session[:participant_id]
              @my_team_id = Participant.find(@participant_id).team.id
              @my_team = Team.find(@my_team_id)
              @advices = InteractionAdvice.find_all_by_assignment_id(params[:assignment_id])
              @advices = @advices.sort{|x,y|x.score<=>y.score}
              @interaction.errors.each { |err| @error += err[1]  + "</br>"}
              flash[:alert] = @error
              render :action => 'new' ,
                     :assignment_id=>params[:assign],
                     :type=>params[:type], :id=>session[:participant_id], :interaction => @interaction
            end
          else
            flash[:alert] = "Interaction already reported."
            redirect_to :controller=>'interaction', :action=>'view', :id=>session[:participant_id]
          end
        else
          @user_name = params[:helper].to_s
          @assignment = params[:assign]
          @type = params[:type]
          @id = session[:participant_id]
          @participant_id = session[:participant_id]
          @my_team_id = Participant.find(@participant_id).team.id
          @my_team = Team.find(@my_team_id)
          @interaction = HelpeeInteraction.new(params[:interactions])
          @advices = InteractionAdvice.find_all_by_assignment_id(params[:assignment_id])
          @advices = @advices.sort{|x,y|x.score<=>y.score}
          flash[:alert] = "Dont act smart. User cant belong to the same team!"
          render :action => 'new' ,
                 :assignment_id=>params[:assign], :type=>params[:type], :id=>session[:participant_id], :interaction => @interaction
        end
      end

      #for helper entries into the table
    elsif (params[:type]=="helper")
      @selected_team=Team.first(:conditions => ['parent_id=? and name=?',params[:assign],params[:teams]])
      helper_record1 = HelperInteraction.first(:conditions => ["participant_id = ? AND team_id = ?",session[:participant_id],@selected_team.id ])
      # check if current helper interaction already exists
      if @helper_record1
        flash[:alert] ="Interaction already reported.."
        redirect_to :action => 'new' , :assignment_id=>params[:assign], :type=>params[:type], :id=>session[:participant_id]
      else
        @interaction = HelperInteraction.new(params[:interactions])
        @interaction.participant_id=session[:participant_id]
        @interaction.interaction_datetime=params[:interaction_date]
        @interaction.team_id=@selected_team.id
        @interaction.status='Not Confirmed'
        if @interaction.save
          @helpee_record2 = HelpeeInteraction.first(:conditions => ["participant_id = ? AND team_id = ?", @interaction.participant_id,
                                                                    @interaction.team_id ])
          if @helpee_record2
            @helpee_record2.update_attribute('status','Confirmed')
            @helper_record2=HelperInteraction.first(:conditions => ["participant_id = ? AND team_id = ?", @interaction.participant_id,
                                                                    @interaction.team_id ])
            @helper_record2.update_attribute('status','Confirmed')
          end
          flash[:note] =" Interaction created successfully."
          redirect_to :controller=>'interaction', :action=>'view',:assignment=>params[:assign], :id=>session[:participant_id]
          # display errors
        else
          @error = ""
          @assignment = params[:assign]
          @type = params[:type]
          @id = session[:participant_id]
          @participant_id = session[:participant_id]
          @interaction.errors.each { |err| @error += err[1]  + "</br>"}
          flash[:alert] = @error
          render :action => 'new' ,
                 :assignment_id=>params[:assign], :type=>params[:type], :id=>session[:participant_id], :interaction => @interaction
        end
      end
    end
  end

  def new
    @user_name = ""
    @assignment=params[:assignment_id]
    @participant_id = params[:id]
    @my_team_id = Participant.find(@participant_id).team.id
    @my_team = Team.find(@my_team_id)
    @interaction = params[:interaction]
    if(params[:type]=='helper')
      if !@interaction
        @interaction=HelperInteraction.new
      end
      session[:participant_id] = params[:id]
    elsif(params[:type]=='helpee')
      if !@interaction
        @interaction=HelpeeInteraction.new
      end
      session[:participant_id] = params[:id]
    end
    #for display of advices for the scores
    @type = params[:type]
    @id=params[:id]
    @advices = InteractionAdvice.find_all_by_assignment_id(params[:assignment_id])
    @advices = @advices.sort{|x,y|x.score<=>y.score}
  end

  #module to show interaction details and approve interaction by instructor

  def interaction_view
    #  if show interaction details
    if params[:type]=='Show'
      @interaction = Interaction.find(params[:id])
      @helper_record = HelperInteraction.first(:conditions => ["participant_id = ? AND team_id = ?", @interaction.participant_id,@interaction.team_id ])
      @helpee_record = HelpeeInteraction.first(:conditions => ["participant_id = ? AND team_id = ?",@interaction.participant_id,@interaction.team_id ])
      render :partial=>  'instructor_view', :locals => {:interaction=>@interaction ,:id=>params[:id],:expanded => (params[:expanded])}
      # if approve interaction
    else
      @interaction = Interaction.find(params[:id])
      @interaction.update_attribute("status","Approved")
      helper=HelperInteraction.first(:conditions => ["participant_id = ? AND team_id = ?", @interaction.participant_id,@interaction.team_id ])
      helper.update_attribute("status","Approved")
      render :partial=>  'instructor_view', :locals => {:interaction=>@interaction ,:id=>params[:id],:expanded => (params[:expanded])}
    end
  end

  def expand_details
    interaction = Interaction.find(params[:interaction])
    @helper_record = HelperInteraction.find(interaction.helper_entry)
    if !@helper_record
      @helper_record = HelperInteraction.new
    end
    @helpee_record = HelpeeInteraction.find(interaction.helpee_entry)
    if !@helpee_record
      @helpee_record = HelpeeInteraction.new
    end
    render :partial => 'interaction', :locals => {:interaction => @interaction , :type=>params[:type] , :expanded => (params[:expanded])}
  end

  def edit_advice
    @advices = InteractionAdvice.find_all_by_assignment_id(params[:id])
    @id = params[:id]
  end

  def update_advice
    flash[:alert] = InteractionAdvice.update_advice(params[:advices],params[:assign])
    if !flash[:alert].nil?
      redirect_to :controller => :interaction , :action => :edit_advice ,:id => params[:assign]
    else
      flash[:note] = "Advice added sucessfully"
      redirect_to :controller => :assignment , :action => :edit ,:id => params[:assign]
    end
  end

end
